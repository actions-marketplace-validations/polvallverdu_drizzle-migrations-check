import { boolean, pgTable, text, uuid } from "drizzle-orm/pg-core";

export const apiKeys = pgTable("api_keys", {
  id: uuid("id").primaryKey().defaultRandom(),
  label: text("label").notNull(),
  revoked: boolean("revoked").default(false).notNull(),
  // @drift
});
