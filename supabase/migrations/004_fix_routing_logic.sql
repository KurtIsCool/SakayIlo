-- Migration: Fix Routing Logic and Data Integrity

-- 1. Fix insert_route to force merging of linestrings
CREATE OR REPLACE FUNCTION insert_route(
    p_route_name text,
    p_formal_name text,
    p_color text,
    p_geo_json json
)
RETURNS void
LANGUAGE plpgsql
AS $$
BEGIN
    INSERT INTO routes (route_name, formal_name, color, path)
    VALUES (
        p_route_name,
        p_formal_name,
        p_color,
        -- Attempt to merge segments into a single LineString if possible
        ST_LineMerge(ST_SetSRID(ST_GeomFromGeoJSON(p_geo_json), 4326))::geography
    );
END;
$$;

-- 2. Update existing routes to be merged (Best Effort)
UPDATE routes
SET path = ST_LineMerge(path::geometry)::geography;

-- 3. Enhanced find_best_route
-- Supports Loops (wrapping) and Sorting Preferences
CREATE OR REPLACE FUNCTION find_best_route(
    user_lat double precision,
    user_lng double precision,
    dest_lat double precision,
    dest_lng double precision,
    sort_mode text DEFAULT 'fastest', -- 'fastest', 'cheapest', 'transfers'
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
    dropoff_fraction double precision,
    is_loop_ride boolean
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
            (ST_Dump(r.path::geometry)).geom as path_geom
        FROM routes r
        WHERE
            r.is_active = true
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
            ST_ClosestPoint(nr.path_geom, user_geom) as pickup_geom,
            ST_ClosestPoint(nr.path_geom, dest_geom) as dropoff_geom,
            ST_IsClosed(nr.path_geom) as is_closed_geom -- Check if geometry is technically closed
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
            ST_LineLocatePoint(cp.path_geom, cp.pickup_geom) as p_frac,
            ST_LineLocatePoint(cp.path_geom, cp.dropoff_geom) as d_frac,
            ST_Distance(cp.pickup_geom::geography, user_geom::geography) as walk1_dist,
            ST_Distance(cp.dropoff_geom::geography, dest_geom::geography) as walk2_dist,

            -- Detect effective loop: geometry is closed OR start/end are very close (within 100m)
            (cp.is_closed_geom OR ST_DWithin(ST_StartPoint(cp.path_geom)::geography, ST_EndPoint(cp.path_geom)::geography, 100)) as is_effective_loop
        FROM calculated_points cp
    ),
    valid_directions AS (
        SELECT
            *,
            -- Valid if p < d OR (it is a loop AND p > d)
            CASE
                WHEN p_frac <= d_frac THEN true
                WHEN p_frac > d_frac AND is_effective_loop THEN true
                ELSE false
            END as is_valid,

            -- Calculate Ride Distance (approximate using fractions for sorting)
            CASE
                WHEN p_frac <= d_frac THEN (d_frac - p_frac)
                ELSE (1.0 - p_frac) + d_frac -- Wrap around distance fraction
            END as ride_frac_score
        FROM scored_routes
    )
    SELECT
        vd.id as route_id,
        vd.route_name,
        vd.formal_name,
        vd.color,
        (vd.walk1_dist + vd.walk2_dist) as total_walking_distance_meters,
        ST_AsGeoJSON(vd.pickup_geom) as pickup_point_geojson,
        ST_AsGeoJSON(vd.dropoff_geom) as dropoff_point_geojson,

        -- Generate Segment Geometry
        ST_AsGeoJSON(
            CASE
                WHEN vd.p_frac <= vd.d_frac THEN
                    ST_LineSubstring(vd.path_geom, vd.p_frac, vd.d_frac)
                ELSE
                    -- Wrap around: Union of (P -> End) and (Start -> D)
                    ST_MakeLine(
                        ST_LineSubstring(vd.path_geom, vd.p_frac, 1.0),
                        ST_LineSubstring(vd.path_geom, 0.0, vd.d_frac)
                    )
            END
        ) as route_segment_geojson,

        vd.p_frac as pickup_fraction,
        vd.d_frac as dropoff_fraction,
        (vd.p_frac > vd.d_frac) as is_loop_ride
    FROM valid_directions vd
    WHERE vd.is_valid = true
    ORDER BY
        -- Dynamic Sorting
        CASE WHEN sort_mode = 'cheapest' THEN
             vd.ride_frac_score -- Shortest ride assumed cheapest
        ELSE
             (vd.walk1_dist + vd.walk2_dist) -- Default/Fastest/Transfers prioritizes less walking first
        END ASC,

        -- Secondary sorts
        CASE WHEN sort_mode = 'fastest' THEN
             vd.ride_frac_score -- Then shortest ride
        ELSE
             (vd.walk1_dist + vd.walk2_dist)
        END ASC
    LIMIT 5;
END;
$$;
