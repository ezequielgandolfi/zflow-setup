-- Widget widths were 1–12 columns; they snap to the nearest of small (3), medium (6) and large (12). Heights are
-- capped at 10 rows.
UPDATE `dashboards` SET `groups` = (
	SELECT json_group_array(json(json_set(g.value, '$.widgets', (
		SELECT json_group_array(json(json_set(json_remove(w.value, '$.columns'), '$.rows', min(w.value ->> '$.rows', 10), '$.width', CASE
			WHEN w.value ->> '$.columns' <= 4 THEN 'small'
			WHEN w.value ->> '$.columns' <= 9 THEN 'medium'
			ELSE 'large'
		END)) ORDER BY w.key)
		FROM json_each(g.value, '$.widgets') AS w
	))) ORDER BY g.key)
	FROM json_each(`dashboards`.`groups`) AS g
);
