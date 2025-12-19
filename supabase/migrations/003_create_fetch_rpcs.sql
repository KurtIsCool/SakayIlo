-- Migration: Create RPCs for fetching route geometries

-- 1. Get a single route's full path as GeoJSON
CREATE OR REPLACE FUNCTION get_route_path(
    route_id bigint
)
RETURNS TABLE (
    route_id bigint,
    route_name text,
    color text,
    path_geojson text
)
LANGUAGE plpgsql
AS $$
BEGIN
    RETURN QUERY
    SELECT
        r.id,
        r.route_name,
        r.color,
        ST_AsGeoJSON(r.path) as path_geojson
    FROM routes r
    WHERE r.id = route_id;
END;
$$;

-- 2. Get all routes paths (simplified) for background display
-- Using ST_Simplify to reduce payload size for the "subtle lines" view
CREATE OR REPLACE FUNCTION get_all_routes_paths()
RETURNS TABLE (
    route_id bigint,
    color text,
    path_geojson text
)
LANGUAGE plpgsql
AS $$
BEGIN
    RETURN QUERY
    SELECT
        r.id,
        r.color,
        ST_AsGeoJSON(ST_Simplify(r.path::geometry, 0.0001)) as path_geojson
    FROM routes r
    WHERE r.is_active = true;
END;
$$;
