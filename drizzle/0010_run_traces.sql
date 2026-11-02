CREATE TABLE `captures` (
	`automation_id` text PRIMARY KEY NOT NULL,
	`project_id` text NOT NULL,
	`enabled_at` integer NOT NULL,
	FOREIGN KEY (`automation_id`) REFERENCES `automations`(`id`) ON UPDATE no action ON DELETE cascade,
	FOREIGN KEY (`project_id`) REFERENCES `projects`(`id`) ON UPDATE no action ON DELETE cascade
);
--> statement-breakpoint
CREATE TABLE `run_traces` (
	`run_id` text PRIMARY KEY NOT NULL,
	`project_id` text NOT NULL,
	`automation_id` text NOT NULL,
	`automation_name` text NOT NULL,
	`version` integer,
	`test` integer NOT NULL,
	`parent_run_id` text,
	`status` text NOT NULL,
	`error` text,
	`started_at` integer NOT NULL,
	`finished_at` integer NOT NULL,
	`truncated` integer NOT NULL,
	`automation` text NOT NULL,
	`events` text NOT NULL,
	FOREIGN KEY (`project_id`) REFERENCES `projects`(`id`) ON UPDATE no action ON DELETE cascade,
	FOREIGN KEY (`automation_id`) REFERENCES `automations`(`id`) ON UPDATE no action ON DELETE cascade
);
--> statement-breakpoint
CREATE INDEX `run_traces_automation_idx` ON `run_traces` (`automation_id`,`started_at`);