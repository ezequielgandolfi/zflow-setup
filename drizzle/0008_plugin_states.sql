CREATE TABLE `plugin_states` (
	`id` text PRIMARY KEY NOT NULL,
	`repo` text,
	`version` text,
	`disabled` integer DEFAULT false NOT NULL,
	`latest_version` text,
	`checked_at` integer,
	`updated_at` integer NOT NULL
);
