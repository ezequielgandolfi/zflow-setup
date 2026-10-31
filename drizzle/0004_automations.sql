-- Flows were renamed to automations, and runner bindings point at them with `automationId` instead of `flowId`.
ALTER TABLE `flows` RENAME TO `automations`;--> statement-breakpoint
DROP INDEX `flows_project_idx`;--> statement-breakpoint
CREATE INDEX `automations_project_idx` ON `automations` (`project_id`);--> statement-breakpoint
UPDATE `runners` SET `bindings` = (
	SELECT json_group_array(json(json_set(json_remove(b.value, '$.flowId'), '$.automationId', b.value ->> '$.flowId')) ORDER BY b.key)
	FROM json_each(`runners`.`bindings`) AS b
);
