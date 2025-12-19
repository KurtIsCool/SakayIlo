-- Migration: Create Routing RPC functions

-- Enable PostGIS if not already (just in case, though verify script showed it is used)
CREATE EXTENSION IF NOT EXISTS postgis;

-- 1. Main Routing Function: find_best_route
-- Finds routes that pass close to both origin and destination.
-- Returns details including the geometry of the route and specific pickup/dropoff points.

CREATE OR REPLACE FUNCTION find_best_route(
    user_lat double precision,
    user_lng double precision,
    dest_lat double precision,
    dest_lng double precision,
    search_radius_meters double precision DEFAULT 600
)
RETURNS TABLE (
    route_id uuid,
    route_name text,
    formal_name text,
    color text,
    total_walking_distance_meters double precision,
    pickup_point_geojson text,
    dropoff_point_geojson text,
    route_segment_geojson text,
    pickup_fraction double precision,
    dropoff_fraction double precision
)
LANGUAGE plpgsql
AS $$
DECLARE
    user_geom geometry;
    dest_geom geometry;
BEGIN
    -- Create geometry points from input (SRID 4326)
    user_geom := ST_SetSRID(ST_Point(user_lng, user_lat), 4326);
    dest_geom := ST_SetSRID(ST_Point(dest_lng, dest_lat), 4326);

    RETURN QUERY
    WITH nearby_routes AS (
        SELECT
            r.id,
            r.route_name,
            r.formal_name,
            r.color,
            -- Explode MultiLineString into individual LineStrings using ST_Dump
            -- This ensures we check every segment of the route, not just the first one.
            (ST_Dump(r.path::geometry)).geom as path_geom
        FROM routes r
        WHERE
            r.is_active = true
            -- Pre-filter using the geography index on the full MultiLineString
            AND ST_DWithin(r.path, user_geom::geography, search_radius_meters)
            AND ST_DWithin(r.path, dest_geom::geography, search_radius_meters)
    ),
    calculated_points AS (
        SELECT
            nr.id,
            nr.route_name,
            nr.formal_name,
            nr.color,
            nr.path_geom,
            -- Calculate closest point on this segment to USER (Pickup)
            ST_ClosestPoint(nr.path_geom, user_geom) as pickup_geom,
            -- Calculate closest point on this segment to DESTINATION (Dropoff)
            ST_ClosestPoint(nr.path_geom, dest_geom) as dropoff_geom
        FROM nearby_routes nr
    ),
    scored_routes AS (
        SELECT
            cp.id,
            cp.route_name,
            cp.formal_name,
            cp.color,
            cp.path_geom,
            cp.pickup_geom,
            cp.dropoff_geom,
            -- Fractions to check direction
            ST_LineLocatePoint(cp.path_geom, cp.pickup_geom) as p_frac,
            ST_LineLocatePoint(cp.path_geom, cp.dropoff_geom) as d_frac,
            -- Distances
            ST_Distance(cp.pickup_geom::geography, user_geom::geography) as walk1_dist,
            ST_Distance(cp.dropoff_geom::geography, dest_geom::geography) as walk2_dist
        FROM calculated_points cp
    )
    SELECT
        sr.id as route_id,
        sr.route_name,
        sr.formal_name,
        sr.color,
        (sr.walk1_dist + sr.walk2_dist) as total_walking_distance_meters,
        ST_AsGeoJSON(sr.pickup_geom) as pickup_point_geojson,
        ST_AsGeoJSON(sr.dropoff_geom) as dropoff_point_geojson,
        -- Return the ride segment using ST_LineSubstring
        ST_AsGeoJSON(ST_LineSubstring(sr.path_geom, sr.p_frac, sr.d_frac)) as route_segment_geojson,
        sr.p_frac as pickup_fraction,
        sr.d_frac as dropoff_fraction
    FROM scored_routes sr
    WHERE
        sr.p_frac < sr.d_frac -- Directionality check: pickup must be before dropoff on this segment
    ORDER BY
        (sr.walk1_dist + sr.walk2_dist) ASC, -- Prioritize less walking
        (sr.d_frac - sr.p_frac) ASC          -- Then shortest ride
    LIMIT 5;
END;
$$;
