import { integer, pgTable, serial, text } from "drizzle-orm/pg-core";

export const invoices = pgTable("invoices", {
  id: serial("id").primaryKey(),
  customerId: text("customer_id").notNull(),
  amountCents: integer("amount_cents").notNull(),
  // @drift
});
