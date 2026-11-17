-- Weather forecast widgets keep their latitude and longitude as a "Somewhere else" location, now that "Home" exists.
UPDATE `dashboards` SET `groups` = (
	SELECT json_group_array(json(json_set(g.value, '$.widgets', (
		SELECT json_group_array(json(CASE
			WHEN w.value ->> '$.type' = 'weather.forecast' AND w.value ->> '$.config.latitude' IS NOT NULL THEN json_set(
				json_remove(w.value, '$.config.latitude', '$.config.longitude'),
				'$.config.place', 'custom',
				'$.config.location', json_object(
					'latitude', w.value -> '$.config.latitude',
					'longitude', w.value -> '$.config.longitude'
				)
			)
			ELSE w.value
		END) ORDER BY w.key)
		FROM json_each(g.value, '$.widgets') AS w
	))) ORDER BY g.key)
	FROM json_each(`dashboards`.`groups`) AS g
)
WHERE `groups` LIKE '%weather.forecast%';
