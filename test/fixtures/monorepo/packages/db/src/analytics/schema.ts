import { jsonb, pgTable, serial, text, timestamp } from "drizzle-orm/pg-core";

export const events = pgTable("events", {
  id: serial("id").primaryKey(),
  name: text("name").notNull(),
  payload: jsonb("payload"),
  // @drift
  occurredAt: timestamp("occurred_at").defaultNow().notNull(),
});
