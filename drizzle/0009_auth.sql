CREATE TABLE `sessions` (
	`token_hash` text PRIMARY KEY NOT NULL,
	`kind` text NOT NULL,
	`share_link_id` text,
	`expires_at` integer,
	`created_at` integer NOT NULL,
	FOREIGN KEY (`share_link_id`) REFERENCES `share_links`(`id`) ON UPDATE no action ON DELETE cascade
);
--> statement-breakpoint
CREATE TABLE `share_links` (
	`id` text PRIMARY KEY NOT NULL,
	`token_hash` text NOT NULL,
	`project_id` text NOT NULL,
	`dashboard_id` text NOT NULL,
	`label` text NOT NULL,
	`allow_actions` integer NOT NULL,
	`expires_at` integer,
	`created_at` integer NOT NULL,
	`last_used_at` integer,
	FOREIGN KEY (`project_id`) REFERENCES `projects`(`id`) ON UPDATE no action ON DELETE cascade
);
--> statement-breakpoint
CREATE UNIQUE INDEX `share_links_token_idx` ON `share_links` (`token_hash`);