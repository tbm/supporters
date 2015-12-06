-- Conservancy Supporter Database, Version 0.2

DROP TABLE IF EXISTS "supporter";

CREATE TABLE "supporter" (
    "id" integer NOT NULL PRIMARY KEY,
    "ledger_entity_id" varchar(300) NOT NULL UNIQUE,
    "postal_address_id " integer,
    "email_address_id " integer,
    "display_name" varchar(300),
    "public_ack"   bool NOT NULL,
);

CREATE TABLE "request" (
    "id" integer NOT NULL PRIMARY KEY,
    "supporter_id" integer NOT NULL,
    "request_type_id" integer NOT NULL,
    "request_configuration_id" integer,
    "date_requested" date NOT NULL,
    "fulfillment_id" integer,
    "notes" TEXT
    );

CREATE TABLE "request_configuration" (
    "id" integer NOT NULL PRIMARY KEY,
    "request_type_id" integer NOT NULL,
    "description"   varchar(100) NOT NULL,
    );

CREATE TABLE "fulfillment" (
    "id" integer NOT NULL PRIMARY KEY,
    "date" TEXT NOT NULL,
    "who" varchar(300) NOT NULL,
    "how" TEXT,
);

CREATE TABLE "request_type" (
    "id" integer NOT NULL PRIMARY KEY,
    "type"   varchar(100) NOT NULL,
    );

CREATE TABLE "email_address" (
    "id" integer NOT NULL PRIMARY KEY,
    "email_address" varchar(300) NOT NULL UNIQUE,
    "type_id" integer,
    "date_encountered" date NOT NULL,
    );

CREATE TABLE "supporter_email_address_mapping" (
    "supporter_id" integer NOT NULL,
    "email_address_id integer NOT NULL,
    "preferred" bool,
    PRIMARY KEY(supporter_id, email_address_id)
    );

CREATE UNIQUE INDEX supporter2email_single_prefferred_per_supporter
   ON supporter2email(supporter_id, preferred);
   
CREATE TABLE "address_type" (
    "id" integer NOT NULL PRIMARY KEY,
    "name" varchar(50) NOT NULL UNIQUE,
    );

CREATE TABLE "postal_address" (
    "id" integer NOT NULL PRIMARY KEY,
    "formatted_address" varchar(5000),
    "type_id" INTEGER NOT NULL,
    "date_encountered" date NOT NULL,
    );

CREATE TABLE "supporter_postal_address_mapping" (
    "postal_address_id integer NOT NULL,
    "preferred" bool,
    PRIMARY KEY(supporter_id, email_address_id)
    );

CREATE UNIQUE INDEX supporter2postal_single_prefferred_per_supporter
   ON supporter2email(supporter_id, preferred);
   
