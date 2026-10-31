CREATE TABLE `runs` (
	`id` text PRIMARY KEY NOT NULL,
	`project_id` text NOT NULL,
	`version` integer,
	`automation_id` text NOT NULL,
	`automation_name` text NOT NULL,
	`runner_id` text NOT NULL,
	`runner_name` text NOT NULL,
	`parent_run_id` text,
	`status` text NOT NULL,
	`started_at` integer NOT NULL,
	`finished_at` integer,
	`error` text,
	`failed_step` text,
	FOREIGN KEY (`project_id`) REFERENCES `projects`(`id`) ON UPDATE no action ON DELETE cascade
);
--> statement-breakpoint
CREATE INDEX `runs_started_idx` ON `runs` (`started_at`);--> statement-breakpoint
CREATE INDEX `runs_project_started_idx` ON `runs` (`project_id`,`started_at`);