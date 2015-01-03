DROP TABLE IF EXISTS "supporters";

CREATE TABLE "supporters" (
    "id" integer NOT NULL PRIMARY KEY,
    "paypal_payer" varchar(300) NOT NULL UNIQUE,
    "ledger_entity_id" varchar(300) NOT NULL UNIQUE,
    "display_name" varchar(300),
    "public_ack"   bool NOT NULL,
    "want_gift"    bool NOT NULL,
    "join_list"    bool,
    "shirt_size"   varchar(10),
    "gift_sent"    integer NOT NULL DEFAULT 0,
    "on_announce_mailman_list" bool NOT NULL DEFAULT 0,
    "formatted_address" varchar(5000)
);

