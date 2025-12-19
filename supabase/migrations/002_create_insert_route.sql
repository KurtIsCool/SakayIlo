-- Migration: Create Insert Route RPC

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
        ST_SetSRID(ST_GeomFromGeoJSON(p_geo_json), 4326)::geography
    );
END;
$$;
