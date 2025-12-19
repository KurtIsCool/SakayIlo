# SakayIlo - Architecture & Implementation Plan

**Project:** SakayIlo
**Role:** Senior Mobile App Architect
**Target:** Iloilo City Commuters
**Status:** Deployment-Ready Architectural Plan

---

## 1. App Screen Structure

The UI design follows a "Simple, Calm, Reassuring" tone, prioritizing map interactions and clear instructions.

### A. Launch & Permissions
1.  **Splash Screen**: App Logo + "SakayIlo" (Clean, minimal). Background loads cached data.
2.  **Permission Request Overlay**:
    *   **Context**: "To show you the best jeepney nearby, we need your location."
    *   **Action**: "Allow Location Access" (System Prompt).
    *   **Fallback**: Manual location selection if denied.

### B. Home Screen (The "Where?")
*   **Full-Screen Map**:
    *   **User Pin**: Pulsing blue dot (current location).
    *   **Floating Search Bar**: Top center. Placeholder: "Where are you going?"
    *   **Quick Actions (Bottom Sheet - Collapsed)**: "Work", "Home", "SM City", "Megaworld".
*   **Interactions**:
    *   Pan/Zoom map.
    *   Tap "Where are you going?" to enter Search Mode.

### C. Search Mode (Input)
*   **Search Interface**:
    *   **From**: Defaults to "Current Location" (editable).
    *   **To**: Auto-focus.
    *   **Results List**: Autocomplete addresses/landmarks (restricted to Iloilo City bounding box).
*   **Action**: Selecting a result triggers "Processing".

### D. Processing State
*   **Overlay**: "Scanning nearby jeepney routes..."
*   **Visual**: Subtle radar animation on the map.

### E. Results Screen (The "Options")
*   **Map**: Shows User Pin, Destination Pin, and the top-recommended Route Line.
*   **Bottom Sheet (Half-Expanded)**:
    *   **Header**: "Best Ride" (Green badge).
    *   **Route Card**:
        *   **Route Name/Color**: e.g., "Villa - Mohon" (Purple).
        *   **Action**: "Walk 3 mins (150m) to board."
        *   **Metric**: "Total: 18 mins • ₱13.00" (Estimated).
    *   **List**: Scroll down for other options (ranked by efficiency).

### F. Route Detail & Journey (The "Guide")
*   **Mode**: Navigation-like interface.
*   **Visuals**:
    *   **Walking Line (Dotted)**: User -> Boarding Point.
    *   **Boarding Point**: "Wait here" marker on the route line.
    *   **Jeep Line (Solid)**: Boarding Point -> Drop-off Point.
    *   **Walking Line (Dotted)**: Drop-off Point -> Destination.
*   **Confidence Note**: "Jeepneys stop anywhere along this line. Wave to hail."
*   **Step-by-Step Cards**:
    1.  "Walk 150m to [Street Name]."
    2.  "Wait for [Route Name] (Color/Signboard)."
    3.  "Ride for ~12 mins."
    4.  "Get off at [Landmark/Street]."
    5.  "Walk to destination."

---

## 2. User Flow

1.  **Open App** -> Check Location Permissions.
2.  **Home** -> User confirms location is accurate.
3.  **Input** -> User enters Destination.
4.  **Compute** -> App sends User Lat/Lng + Dest Lat/Lng to Supabase RPC.
5.  **Select** -> User picks the best route.
6.  **Guide** -> User follows walking directions to the line -> Boards -> Rides -> Alights -> Arrives.

---

## 3. Database Schema

The database relies on a single source of truth for routes, optimized for PostGIS spatial queries.

### Table: `routes`
*(Verified Existing Table)*

| Column | Type | Description |
| :--- | :--- | :--- |
| `id` | `uuid` | Primary Key. |
| `route_name` | `text` | Display name (e.g., "Jaro CPU"). |
| `formal_name` | `text` | LTFRB formal franchise name. |
| `color` | `text` | UI color code (e.g., "#FF0000"). |
| `path` | `geography(MultiLineString, 4326)` | **The Route Line**. Stores the physical path. |
| `is_active` | `boolean` | If false, filter out. |
| `last_verified` | `timestamp` | Data freshness. |

### Proposed RPCs (Stored Procedures)

We do **not** query the `routes` table directly from the client. We use RPCs to encapsulate logic.

#### `find_best_route(user_lat, user_lng, dest_lat, dest_lng)`
*   **Inputs**: Coordinates.
*   **Logic**:
    1.  **Buffer Search**: Find routes that pass within 400m of *User* AND 400m of *Destination*.
    2.  **Projection**: Calculate:
        *   `pickup_point`: Closest point on line to User.
        *   `dropoff_point`: Closest point on line to Destination.
    3.  **Directionality Check**: Ensure `pickup_point` is *before* `dropoff_point` along the line (using `ST_LineLocatePoint`).
    4.  **Distance Calculation**:
        *   Walk 1: User to Pickup.
        *   Ride: Pickup to Dropoff (along line).
        *   Walk 2: Dropoff to Destination.
    5.  **Ordering**: Sort by (Walk 1 + Walk 2) distance asc, then Ride distance.
*   **Returns**: JSON object with route details and geometry (GeoJSON).

---

## 4. Route-Matching Algorithm (SQL Logic)

This SQL logic will be encapsulated in the `find_best_route` function.

```sql
-- Conceptual SQL Logic for Point-to-Line Routing
WITH nearby_routes AS (
    SELECT
        id, route_name, color, path,
        -- Calculate closest point on route to USER
        ST_ClosestPoint(path::geometry, ST_SetSRID(ST_Point(user_lng, user_lat), 4326)::geometry) as pickup_geom,
        -- Calculate closest point on route to DESTINATION
        ST_ClosestPoint(path::geometry, ST_SetSRID(ST_Point(dest_lng, dest_lat), 4326)::geometry) as dropoff_geom
    FROM routes
    WHERE
        ST_DWithin(path, ST_SetSRID(ST_Point(user_lng, user_lat), 4326), 600) -- Expand search radius slightly
        AND
        ST_DWithin(path, ST_SetSRID(ST_Point(dest_lng, dest_lat), 4326), 600)
        AND is_active = true
)
SELECT
    id, route_name, color,
    -- Get fraction of line to check direction
    ST_LineLocatePoint(path::geometry, pickup_geom) as pickup_frac,
    ST_LineLocatePoint(path::geometry, dropoff_geom) as dropoff_frac,
    -- Return Geometries as GeoJSON
    ST_AsGeoJSON(pickup_geom) as pickup_point,
    ST_AsGeoJSON(dropoff_geom) as dropoff_point,
    ST_AsGeoJSON(path) as route_line
FROM nearby_routes
WHERE
    -- PRIMARY FILTER: Ensure pickup is before dropoff (for non-loop logic, or simple directionality)
    ST_LineLocatePoint(path::geometry, pickup_geom) < ST_LineLocatePoint(path::geometry, dropoff_geom)
ORDER BY
    -- Ranking: Shortest walking distance (Start->Pickup + Dropoff->End)
    (ST_Distance(pickup_geom::geography, ST_SetSRID(ST_Point(user_lng, user_lat), 4326)::geography) +
     ST_Distance(dropoff_geom::geography, ST_SetSRID(ST_Point(dest_lng, dest_lat), 4326)::geography)) ASC
LIMIT 5;
```

*Refinement*: For loop routes, simple fraction comparison might fail if the trip crosses the start/end point of the LineString. For version 1, we assume LineStrings are defined logically A->B or we accept only sub-segments. Given the strictness, we'll start with the linear assumption.

---

## 5. Offline Caching Strategy (Phase 2 - Planned)

*Current Status: The application currently operates in "Online Only" mode. Offline features are planned for future phases.*

Since network connectivity can be spotty, the app goal is to eventually be "Offline First".

1.  **Bootstrapping**: On first launch, fetch *all* active route geometries (`id`, `name`, `color`, `simplified_path`) and store them locally.
    *   Format: GeoJSON FeatureCollection.
    *   Storage: `AsyncStorage` (React Native) or `IndexedDB` (Web).
2.  **Offline Routing (Turf.js)**:
    *   If API fails, switch to **Client-Side Mode**.
    *   Use `Turf.js` to replicate the SQL logic:
        *   `turf.pointToLineDistance` to find candidate routes.
        *   `turf.nearestPointOnLine` to find pickup/dropoff coordinates.
        *   `turf.lineSlice` to extract the ride segment.
        *   `turf.distance` for walking estimations.
3.  **Update Policy**: Check for route updates (`last_verified` timestamp) on app foregrounding.

---

## 6. Implementation Guidance

### Technology Stack
*   **Framework**: React Native (Expo) or React PWA (Vite). *Recommendation: React PWA for immediate cross-platform deployment, scalable to Capacitor/Native later.*
*   **Map Engine**: Mapbox GL JS (or `react-map-gl`). It handles GeoJSON lines beautifully and supports vector tiles. Alternatives: Leaflet (lighter, free) if Mapbox pricing is a concern.
*   **State Management**: React Context or Zustand (Keep it simple).
*   **Geospatial Lib**: `Turf.js` (Critical for offline math).

### Critical Development Steps
1.  **Data Layer**: Implement the `find_best_route` RPC in Supabase.
2.  **API Layer**: Create a Typescript service to call the RPC.
3.  **UI/Map**: Set up the map to render `MultiLineString` paths.
4.  **Logic**: Implement the "Walk -> Ride -> Walk" visualization.
