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
            -- Convert MultiLineString to LineString (take the first geometry)
            -- This is required because ST_LineLocatePoint and ST_LineSubstring generally work on LineStrings.
            -- NOTE: If routes have multiple disjoint segments, this logic might need `ST_Dump` lateral join,
            -- but for this architecture, we assume the primary route path is the first component.
            ST_GeometryN(r.path::geometry, 1) as path_geom,
            -- Calculate closest point on route to USER (Pickup)
            ST_ClosestPoint(ST_GeometryN(r.path::geometry, 1), user_geom) as pickup_geom,
            -- Calculate closest point on route to DESTINATION (Dropoff)
            ST_ClosestPoint(ST_GeometryN(r.path::geometry, 1), dest_geom) as dropoff_geom
        FROM routes r
        WHERE
            r.is_active = true
            -- ST_DWithin works fine with Geography MultiLineString
            AND ST_DWithin(r.path, user_geom::geography, search_radius_meters)
            AND ST_DWithin(r.path, dest_geom::geography, search_radius_meters)
    ),
    scored_routes AS (
        SELECT
            nr.id,
            nr.route_name,
            nr.formal_name,
            nr.color,
            nr.path_geom,
            nr.pickup_geom,
            nr.dropoff_geom,
            -- Fractions to check direction (Requires LineString)
            ST_LineLocatePoint(nr.path_geom, nr.pickup_geom) as p_frac,
            ST_LineLocatePoint(nr.path_geom, nr.dropoff_geom) as d_frac,
            -- Distances
            ST_Distance(nr.pickup_geom::geography, user_geom::geography) as walk1_dist,
            ST_Distance(nr.dropoff_geom::geography, dest_geom::geography) as walk2_dist
        FROM nearby_routes nr
    )
    SELECT
        sr.id as route_id,
        sr.route_name,
        sr.formal_name,
        sr.color,
        (sr.walk1_dist + sr.walk2_dist) as total_walking_distance_meters,
        ST_AsGeoJSON(sr.pickup_geom) as pickup_point_geojson,
        ST_AsGeoJSON(sr.dropoff_geom) as dropoff_point_geojson,
        -- Return the ride segment using ST_LineSubstring (Requires LineString)
        ST_AsGeoJSON(ST_LineSubstring(sr.path_geom, sr.p_frac, sr.d_frac)) as route_segment_geojson,
        sr.p_frac as pickup_fraction,
        sr.d_frac as dropoff_fraction
    FROM scored_routes sr
    WHERE
        sr.p_frac < sr.d_frac -- Simple directionality check (User must move forward along the line)
    ORDER BY
        (sr.walk1_dist + sr.walk2_dist) ASC, -- Prioritize less walking
        (sr.d_frac - sr.p_frac) ASC          -- Then shortest ride (roughly)
    LIMIT 5;
END;
$$;
