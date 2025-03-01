-- Views for network following with the Python NetworkX module and the QGEP Python plugins
-- View: qgep_od.vw_network_node

DROP MATERIALIZED VIEW IF EXISTS qgep_od.vw_network_node;

CREATE MATERIALIZED VIEW qgep_od.vw_network_node AS
 SELECT
   row_number() OVER () AS gid,
   nodes.*
 FROM
 (
   SELECT
     obj_id,
     'reach_point' AS type,
     'reach_point' AS node_type,
     level AS level,
     NULL AS usage_current,
     NULL AS cover_level,
     NULL AS backflow_level,
     NULL AS description,
     situation_geometry::geometry(POINTZ,:SRID) AS detail_geometry,
     situation_geometry::geometry(POINTZ,:SRID)
   FROM qgep_od.reach_point

   UNION

   SELECT
     NE.obj_id,
     'wastewater_node' AS type,
     CASE
       WHEN MH.obj_id IS NOT NULL
         THEN 'manhole'
       WHEN WS.obj_id IS NOT NULL
         THEN 'special_WSucture'
       ELSE 'other'
     END AS node_type,
     bottom_level AS level,
     COALESCE( MAX( ch_from.usage_current ), MAX( ch_to.usage_current ) ) AS usage_current,
     MAX( CO.level ) AS cover_level,
     WN.backflow_level AS backflow_level,
     NE.identifier AS description,
     COALESCE( WS.detail_geometry_geometry, WN.situation_geometry ) AS detail_geometry, -- Will contain different geometry types: do not visualize directly. Will be handled by plugin
     WN.situation_geometry
   FROM qgep_od.wastewater_node WN
   LEFT JOIN qgep_od.wastewater_networkelement NE
     ON NE.obj_id = WN.obj_id
   LEFT JOIN qgep_od.wastewater_structure WS
     ON WS.obj_id = NE.fk_wastewater_structure
   LEFT JOIN qgep_od.manhole MH
     ON MH.obj_id = WS.obj_id
   LEFT JOIN qgep_od.structure_part SP
     ON SP.fk_wastewater_structure = WS.obj_id
   LEFT JOIN qgep_od.cover CO
     ON CO.obj_id = SP.obj_id
   LEFT JOIN qgep_od.reach_point RP
     ON NE.obj_id = RP.fk_wastewater_networkelement
   LEFT JOIN qgep_od.reach re_from
     ON re_from.fk_reach_point_from = RP.obj_id
   LEFT JOIN qgep_od.wastewater_networkelement ne_from
     ON ne_from.obj_id = re_from.obj_id
   LEFT JOIN qgep_od.channel ch_from
     ON ch_from.obj_id = ne_from.fk_wastewater_structure
   LEFT JOIN qgep_od.reach re_to
     ON re_to.fk_reach_point_to = RP.obj_id
   LEFT JOIN qgep_od.wastewater_networkelement ne_to
     ON ne_to.obj_id = re_to.obj_id
   LEFT JOIN qgep_od.channel ch_to
     ON ch_to.obj_id = ne_to.fk_wastewater_structure
   GROUP BY NE.obj_id, type, bottom_level, backflow_level, description, WN.situation_geometry, WS.detail_geometry_geometry, WS.obj_id, MH.obj_id, SP.fk_wastewater_structure
  ) AS nodes;


-- View: qgep_od.vw_network_segment

DROP MATERIALIZED VIEW IF EXISTS qgep_od.vw_network_segment;

CREATE MATERIALIZED VIEW qgep_od.vw_network_segment AS
 WITH reach_parts AS (
   SELECT
     row_number() OVER (ORDER BY reach_point.fk_wastewater_networkelement, ST_LineLocatePoint(ST_LineMerge(ST_CurveToLine(ST_Force2D(reach.progression_geometry))), reach_point.situation_geometry)) AS gid,
     reach_point.obj_id,
     reach_point.fk_wastewater_networkelement,
     reach_point.situation_geometry,
     reach.progression_geometry,
     reach.fk_reach_point_from,
     reach.fk_reach_point_to,
     ST_LineMerge(ST_CurveToLine(ST_Force2D(reach.progression_geometry)))::Geometry(LineString, :SRID) AS reach_progression,
     ST_LineLocatePoint(
       ST_LineMerge(ST_CurveToLine(ST_Force2D(reach.progression_geometry))),
       reach_point.situation_geometry
     ) AS pos
   FROM qgep_od.reach_point
   LEFT JOIN qgep_od.reach ON reach_point.fk_wastewater_networkelement::text = reach.obj_id::text
   WHERE reach_point.fk_wastewater_networkelement IS NOT NULL AND reach.progression_geometry IS NOT NULL
   ORDER BY reach_point.obj_id, ST_LineLocatePoint(ST_LineMerge(ST_CurveToLine(reach.progression_geometry)), reach_point.situation_geometry)
 )

 SELECT row_number() OVER () AS gid,
   parts.*
 FROM
 (
   SELECT
     re.obj_id,
     'reach' AS type,
     clear_height,
     ST_Length( COALESCE( reach_progression, progression_geometry ) ) AS length_calc,
     ST_Length( progression_geometry ) AS length_full,
     COALESCE( from_obj_id, fk_reach_point_from ) AS from_obj_id,
     COALESCE( to_obj_id, fk_reach_point_to ) AS to_obj_id,
     fk_reach_point_from AS from_obj_id_interpolate,
     fk_reach_point_to AS to_obj_id_interpolate,
     COALESCE( from_pos, 0 ) AS from_pos,
     COALESCE( to_pos, 1 ) AS to_pos,
     NULL AS bottom_level,
     ch.usage_current AS usage_current,
     mat.abbr_de AS material,
     COALESCE(reach_progression, ST_LineMerge(ST_CurveToLine(ST_Force2D(progression_geometry))))::Geometry(LineString, :SRID) AS progression_geometry,
     ST_LineMerge(ST_CurveToLine(ST_Force2D(progression_geometry)))::geometry(LineString,:SRID) AS detail_geometry
   FROM qgep_od.reach re
   FULL JOIN
   (
     SELECT
       COALESCE(s1.fk_wastewater_networkelement, s2.fk_wastewater_networkelement) AS reach_obj_id,
       COALESCE(s1.obj_id, s2.fk_reach_point_from) AS from_obj_id,
       COALESCE(s2.obj_id, s1.fk_reach_point_to) AS to_obj_id,
       COALESCE(s1.pos, 0::double precision) AS from_pos,
       COALESCE(s2.pos, 1::double precision) AS to_pos,
       ST_LineSubstring(COALESCE(s1.reach_progression, s2.reach_progression),
                        COALESCE(s1.pos, 0::double precision),
                        COALESCE(s2.pos, 1::double precision)) AS reach_progression
     FROM reach_parts s1
     FULL JOIN reach_parts s2 ON s1.gid = (s2.gid - 1) AND s1.fk_wastewater_networkelement::text = s2.fk_wastewater_networkelement::text
     ORDER BY COALESCE(s1.fk_wastewater_networkelement, s2.fk_wastewater_networkelement), COALESCE(s1.pos, 0::double precision)
   ) AS rr
   ON rr.reach_obj_id = re.obj_id
   LEFT JOIN qgep_od.wastewater_networkelement ne ON ne.obj_id = re.obj_id
   LEFT JOIN qgep_od.channel ch ON ch.obj_id = ne.fk_wastewater_structure
   LEFT JOIN qgep_vl.reach_material mat ON re.material = mat.code

   UNION

   SELECT
     connectors.obj_id AS obj_id,
     'special_structure' AS type,
     NULL AS depth,
     ST_Length( progression_geometry ) AS length_calc,
     ST_Length( progression_geometry ) AS length_full,
     from_obj_id,
     to_obj_id,
     from_obj_id AS from_obj_id_interpolate,
     to_obj_id AS to_obj_id_interpolate,
     0 AS from_pos,
     1 AS to_pos,
     bottom_level,
     NULL AS usage_current,
     NULL AS material,
     progression_geometry,
     progression_geometry::geometry(LineString,:SRID) AS detail_geometry

   FROM
   (
     SELECT
     wn_from.obj_id AS obj_id,
     wn_from.obj_id AS from_obj_id,
     rp_from.obj_id AS to_obj_id,
     wn_from.bottom_level AS bottom_level,
     ST_LineFromMultiPoint( ST_Collect(wn_from.situation_geometry, rp_from.situation_geometry ) ) AS progression_geometry
     FROM qgep_od.reach
       LEFT JOIN qgep_od.reach_point rp_from ON rp_from.obj_id = reach.fk_reach_point_from
       LEFT JOIN qgep_od.wastewater_node wn_from ON rp_from.fk_wastewater_networkelement = wn_from.obj_id
     WHERE
       reach.fk_reach_point_from IS NOT NULL
       AND
       wn_from.obj_id IS NOT NULL

     UNION

     SELECT
       wn_to.obj_id AS obj_id,
       rp_to.obj_id AS from_obj_id,
       wn_to.obj_id AS to_obj_id,
       wn_to.bottom_level AS bottom_level,
       ST_LineFromMultiPoint( ST_Collect(rp_to.situation_geometry, wn_to.situation_geometry ) ) AS progression_geometry
     FROM qgep_od.reach
       LEFT JOIN qgep_od.reach_point rp_to ON rp_to.obj_id = reach.fk_reach_point_to
       LEFT JOIN qgep_od.wastewater_node wn_to ON rp_to.fk_wastewater_networkelement = wn_to.obj_id
     WHERE
       reach.fk_reach_point_to IS NOT NULL
     AND
       wn_to.obj_id IS NOT NULL
   ) AS connectors
   LEFT JOIN qgep_od.wastewater_networkelement ne ON ne.obj_id = connectors.obj_id
 ) AS parts
WHERE GeometryType(progression_geometry) <> 'GEOMETRYCOLLECTION';




REFRESH MATERIALIZED view qgep_od.vw_network_node;
REFRESH MATERIALIZED view qgep_od.vw_network_segment;
