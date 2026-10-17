--
-- PostgreSQL database cluster dump
--

\restrict hpH7XtMKDxl8t3S5FRm5UWnA5EN4jBGiHKETUETQ9JBuei5sshmzf5trm3vD8TI

SET default_transaction_read_only = off;

SET client_encoding = 'UTF8';
SET standard_conforming_strings = on;

--
-- Roles
--

CREATE ROLE neondb_owner;
ALTER ROLE neondb_owner WITH SUPERUSER INHERIT CREATEROLE CREATEDB LOGIN REPLICATION BYPASSRLS PASSWORD 'SCRAM-SHA-256$4096:a4bLanmzRB3Z3MFqmhtaIw==$sroLR5ryP2t+42T/jAx7c1ft7LaiP4z1xXa532l9Rsw=:gyIHlb5A+fdo4rOoNX8oVXmHLbGuBu6lYF27alIjqJw=';

--
-- User Configurations
--








\unrestrict hpH7XtMKDxl8t3S5FRm5UWnA5EN4jBGiHKETUETQ9JBuei5sshmzf5trm3vD8TI

--
-- Databases
--

--
-- Database "template1" dump
--

\connect template1

--
-- PostgreSQL database dump
--

\restrict FeGTQRPlaKsSbhdMWv68xlnzFgZq74YFnGIswY0LGeeBKYSwWo4ZuqhWaoXrMj2

-- Dumped from database version 18.6 (Debian 18.6-1.pgdg13+2)
-- Dumped by pg_dump version 18.6 (Debian 18.6-1.pgdg13+2)

SET statement_timeout = 0;
SET lock_timeout = 0;
SET idle_in_transaction_session_timeout = 0;
SET transaction_timeout = 0;
SET client_encoding = 'UTF8';
SET standard_conforming_strings = on;
SELECT pg_catalog.set_config('search_path', '', false);
SET check_function_bodies = false;
SET xmloption = content;
SET client_min_messages = warning;
SET row_security = off;

--
-- PostgreSQL database dump complete
--

\unrestrict FeGTQRPlaKsSbhdMWv68xlnzFgZq74YFnGIswY0LGeeBKYSwWo4ZuqhWaoXrMj2

--
-- Database "neondb" dump
--

--
-- PostgreSQL database dump
--

\restrict frqi9Du4ykRdYaDbVskcbmqFmdqT8SScWznclpreAURqI2rQhlf72CbjlA4Bo9F

-- Dumped from database version 18.6 (Debian 18.6-1.pgdg13+2)
-- Dumped by pg_dump version 18.6 (Debian 18.6-1.pgdg13+2)

SET statement_timeout = 0;
SET lock_timeout = 0;
SET idle_in_transaction_session_timeout = 0;
SET transaction_timeout = 0;
SET client_encoding = 'UTF8';
SET standard_conforming_strings = on;
SELECT pg_catalog.set_config('search_path', '', false);
SET check_function_bodies = false;
SET xmloption = content;
SET client_min_messages = warning;
SET row_security = off;

--
-- Name: neondb; Type: DATABASE; Schema: -; Owner: neondb_owner
--

CREATE DATABASE neondb WITH TEMPLATE = template0 ENCODING = 'UTF8' LOCALE_PROVIDER = libc LOCALE = 'C';


ALTER DATABASE neondb OWNER TO neondb_owner;

\unrestrict frqi9Du4ykRdYaDbVskcbmqFmdqT8SScWznclpreAURqI2rQhlf72CbjlA4Bo9F
\connect neondb
\restrict frqi9Du4ykRdYaDbVskcbmqFmdqT8SScWznclpreAURqI2rQhlf72CbjlA4Bo9F

SET statement_timeout = 0;
SET lock_timeout = 0;
SET idle_in_transaction_session_timeout = 0;
SET transaction_timeout = 0;
SET client_encoding = 'UTF8';
SET standard_conforming_strings = on;
SELECT pg_catalog.set_config('search_path', '', false);
SET check_function_bodies = false;
SET xmloption = content;
SET client_min_messages = warning;
SET row_security = off;

--
-- Name: public; Type: SCHEMA; Schema: -; Owner: neondb_owner
--

-- *not* creating schema, since initdb creates it


ALTER SCHEMA public OWNER TO neondb_owner;

--
-- Name: SCHEMA public; Type: COMMENT; Schema: -; Owner: neondb_owner
--

COMMENT ON SCHEMA public IS '';


--
-- Name: show_db_tree(); Type: FUNCTION; Schema: public; Owner: neondb_owner
--

CREATE FUNCTION public.show_db_tree() RETURNS TABLE(tree_structure text)
    LANGUAGE plpgsql
    AS $$
BEGIN
    -- First show all databases
    RETURN QUERY
    SELECT ':file_folder: ' || datname || ' (DATABASE)'
    FROM pg_database
    WHERE datistemplate = false;

    -- Then show current database structure
    RETURN QUERY
    WITH RECURSIVE
    -- Get schemas
    schemas AS (
        SELECT
            n.nspname AS object_name,
            1 AS level,
            n.nspname AS path,
            'SCHEMA' AS object_type
        FROM pg_namespace n
        WHERE n.nspname NOT LIKE 'pg_%'
        AND n.nspname != 'information_schema'
    ),

    -- Get all objects (tables, views, functions, etc.)
    objects AS (
        SELECT
            c.relname AS object_name,
            2 AS level,
            s.path || ' → ' || c.relname AS path,
            CASE c.relkind
                WHEN 'r' THEN 'TABLE'
                WHEN 'v' THEN 'VIEW'
                WHEN 'm' THEN 'MATERIALIZED VIEW'
                WHEN 'i' THEN 'INDEX'
                WHEN 'S' THEN 'SEQUENCE'
                WHEN 'f' THEN 'FOREIGN TABLE'
            END AS object_type
        FROM pg_class c
        JOIN pg_namespace n ON n.oid = c.relnamespace
        JOIN schemas s ON n.nspname = s.object_name
        WHERE c.relkind IN ('r','v','m','i','S','f')

        UNION ALL

        SELECT
            p.proname AS object_name,
            2 AS level,
            s.path || ' → ' || p.proname AS path,
            'FUNCTION' AS object_type
        FROM pg_proc p
        JOIN pg_namespace n ON n.oid = p.pronamespace
        JOIN schemas s ON n.nspname = s.object_name
    ),

    -- Combine schemas and objects
    combined AS (
        SELECT * FROM schemas
        UNION ALL
        SELECT * FROM objects
    )

    -- Final output with tree-like formatting
    SELECT
        REPEAT('    ', level) ||
        CASE
            WHEN level = 1 THEN '└── :open_file_folder: '
            ELSE '    └── ' ||
                CASE object_type
                    WHEN 'TABLE' THEN ':bar_chart: '
                    WHEN 'VIEW' THEN ':eye: '
                    WHEN 'MATERIALIZED VIEW' THEN ':newspaper: '
                    WHEN 'FUNCTION' THEN ':zap: '
                    WHEN 'INDEX' THEN ':mag: '
                    WHEN 'SEQUENCE' THEN ':1234: '
                    WHEN 'FOREIGN TABLE' THEN ':globe_with_meridians: '
                    ELSE ''
                END
        END || object_name || ' (' || object_type || ')'
    FROM combined
    ORDER BY path;
END;
$$;


ALTER FUNCTION public.show_db_tree() OWNER TO neondb_owner;

SET default_tablespace = '';

SET default_table_access_method = heap;

--
-- Name: aggregate_reference; Type: TABLE; Schema: public; Owner: neondb_owner
--

CREATE TABLE public.aggregate_reference (
    id uuid NOT NULL,
    source character varying(50) NOT NULL,
    country character varying(100) NOT NULL,
    ref_year smallint NOT NULL,
    metric character varying(100) NOT NULL,
    appliance character varying(100),
    value numeric NOT NULL,
    unit character varying(30) NOT NULL,
    CONSTRAINT aggregate_reference_ref_year_check CHECK ((ref_year >= 1900))
);


ALTER TABLE public.aggregate_reference OWNER TO neondb_owner;

--
-- Name: energy_label_class; Type: TABLE; Schema: public; Owner: neondb_owner
--

CREATE TABLE public.energy_label_class (
    id uuid NOT NULL,
    label_class character varying(10) NOT NULL,
    updated_at timestamp with time zone DEFAULT now(),
    CONSTRAINT energy_label_class_label_class_check CHECK (((label_class)::text = ANY ((ARRAY['A+++'::character varying, 'A++'::character varying, 'A+'::character varying, 'A'::character varying, 'B'::character varying, 'C'::character varying, 'D'::character varying, 'E'::character varying, 'F'::character varying, 'G'::character varying])::text[])))
);


ALTER TABLE public.energy_label_class OWNER TO neondb_owner;

--
-- Name: energy_raw_measurement; Type: TABLE; Schema: public; Owner: neondb_owner
--

CREATE TABLE public.energy_raw_measurement (
    id uuid NOT NULL,
    raw_power_w numeric,
    raw_annual_kwh numeric,
    raw_standby_w numeric,
    measurement_date timestamp with time zone DEFAULT now()
);


ALTER TABLE public.energy_raw_measurement OWNER TO neondb_owner;

--
-- Name: energy_specification; Type: TABLE; Schema: public; Owner: neondb_owner
--

CREATE TABLE public.energy_specification (
    product_id uuid NOT NULL,
    source character varying(50) NOT NULL,
    source_product_id character varying(255),
    power_w numeric,
    efficiency_class character varying(10),
    declared_year smallint
);


ALTER TABLE public.energy_specification OWNER TO neondb_owner;

--
-- Name: product; Type: TABLE; Schema: public; Owner: neondb_owner
--

CREATE TABLE public.product (
    id uuid NOT NULL,
    name character varying(150),
    brand character varying(255),
    model character varying(255),
    category character varying(255),
    avg_power_w numeric(38,2),
    annual_energy_kwh numeric(38,2),
    subcategory character varying(255),
    standby_power_w numeric,
    is_generic boolean DEFAULT false,
    avg_idle_energy_for_hour numeric(38,2)
);


ALTER TABLE public.product OWNER TO neondb_owner;

--
-- Name: product_source_observation; Type: TABLE; Schema: public; Owner: neondb_owner
--

CREATE TABLE public.product_source_observation (
    id uuid NOT NULL,
    canonical_product_id uuid NOT NULL,
    source character varying(50) NOT NULL,
    external_id character varying(255) NOT NULL,
    brand character varying(255),
    model character varying(255),
    dataset_id character varying(255),
    power_w numeric,
    annual_energy_kwh numeric,
    standby_power_w numeric,
    observed_at timestamp with time zone DEFAULT now() NOT NULL,
    is_generic boolean DEFAULT false NOT NULL,
    voltage_raw character varying(50),
    voltage_kind character varying(16) DEFAULT 'unknown'::character varying NOT NULL,
    voltage_min_v numeric,
    voltage_max_v numeric,
    raw_energy_value numeric,
    raw_energy_unit character varying(30),
    CONSTRAINT product_source_observation_annual_energy_kwh_check CHECK (((annual_energy_kwh IS NULL) OR (annual_energy_kwh >= (0)::numeric))),
    CONSTRAINT product_source_observation_power_w_check CHECK (((power_w IS NULL) OR (power_w >= (0)::numeric))),
    CONSTRAINT product_source_observation_raw_energy_value_check CHECK (((raw_energy_value IS NULL) OR (raw_energy_value >= (0)::numeric))),
    CONSTRAINT product_source_observation_standby_power_w_check CHECK (((standby_power_w IS NULL) OR (standby_power_w >= (0)::numeric))),
    CONSTRAINT product_source_observation_voltage_kind_check CHECK (((voltage_kind)::text = ANY ((ARRAY['unknown'::character varying, 'monovolt'::character varying, 'bivolt'::character varying, 'range'::character varying])::text[]))),
    CONSTRAINT product_source_observation_voltage_max_v_check CHECK (((voltage_max_v IS NULL) OR (voltage_max_v > (0)::numeric))),
    CONSTRAINT product_source_observation_voltage_min_v_check CHECK (((voltage_min_v IS NULL) OR (voltage_min_v > (0)::numeric)))
);


ALTER TABLE public.product_source_observation OWNER TO neondb_owner;

--
-- Name: registry_user_product; Type: TABLE; Schema: public; Owner: neondb_owner
--

CREATE TABLE public.registry_user_product (
    id uuid CONSTRAINT userproduct_id_not_null NOT NULL,
    avg_active_hours numeric(38,2),
    hours_standby numeric(38,2),
    quantity integer CONSTRAINT userproduct_quantity_not_null NOT NULL,
    product_id uuid CONSTRAINT userproduct_product_id_not_null NOT NULL,
    user_id integer CONSTRAINT userproduct_user_id_not_null NOT NULL
);


ALTER TABLE public.registry_user_product OWNER TO neondb_owner;

--
-- Name: source_metadata; Type: TABLE; Schema: public; Owner: neondb_owner
--

CREATE TABLE public.source_metadata (
    id uuid NOT NULL,
    source character varying(50) NOT NULL,
    metadata_key character varying(100) NOT NULL,
    metadata_value text NOT NULL
);


ALTER TABLE public.source_metadata OWNER TO neondb_owner;

--
-- Name: source_product; Type: TABLE; Schema: public; Owner: neondb_owner
--

CREATE TABLE public.source_product (
    id uuid NOT NULL,
    source character varying(50) NOT NULL,
    source_product_id character varying(255) NOT NULL
);


ALTER TABLE public.source_product OWNER TO neondb_owner;

--
-- Name: users; Type: TABLE; Schema: public; Owner: neondb_owner
--

CREATE TABLE public.users (
    id integer NOT NULL,
    name character varying(50)
);


ALTER TABLE public.users OWNER TO neondb_owner;

--
-- Name: users_id_seq; Type: SEQUENCE; Schema: public; Owner: neondb_owner
--

CREATE SEQUENCE public.users_id_seq
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER SEQUENCE public.users_id_seq OWNER TO neondb_owner;

--
-- Name: users_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: neondb_owner
--

ALTER SEQUENCE public.users_id_seq OWNED BY public.users.id;


--
-- Name: users id; Type: DEFAULT; Schema: public; Owner: neondb_owner
--

ALTER TABLE ONLY public.users ALTER COLUMN id SET DEFAULT nextval('public.users_id_seq'::regclass);


--
-- Data for Name: aggregate_reference; Type: TABLE DATA; Schema: public; Owner: neondb_owner
--

COPY public.aggregate_reference (id, source, country, ref_year, metric, appliance, value, unit) FROM stdin;
\.


--
-- Data for Name: energy_label_class; Type: TABLE DATA; Schema: public; Owner: neondb_owner
--

COPY public.energy_label_class (id, label_class, updated_at) FROM stdin;
17ec2033-1274-587c-9c08-03f16e660662	A+++	2026-10-15 20:58:22.566199+00
a869831f-0baa-5dcf-acf7-29b5bb7baeaf	A	2026-10-15 20:58:22.566199+00
b03224d6-390e-55a5-9ea8-93d8f62bc65c	A+++	2026-10-15 20:58:22.566199+00
\.


--
-- Data for Name: energy_raw_measurement; Type: TABLE DATA; Schema: public; Owner: neondb_owner
--

COPY public.energy_raw_measurement (id, raw_power_w, raw_annual_kwh, raw_standby_w, measurement_date) FROM stdin;
\.


--
-- Data for Name: energy_specification; Type: TABLE DATA; Schema: public; Owner: neondb_owner
--

COPY public.energy_specification (product_id, source, source_product_id, power_w, efficiency_class, declared_year) FROM stdin;
\.


--
-- Data for Name: product; Type: TABLE DATA; Schema: public; Owner: neondb_owner
--

COPY public.product (id, name, brand, model, category, avg_power_w, annual_energy_kwh, subcategory, standby_power_w, is_generic, avg_idle_energy_for_hour) FROM stdin;
e4bf7c93-7db0-58b5-972d-f7882fc7b082	KIP KIP 650	KIP	KIP 650	Eletrônicos	3.20	0.80	Equipamento de imagem	\N	f	\N
ebecd649-8673-5ff5-813c-b93a39d8481e	HP Inc. HP DesignJet T1600 Printer Series; HP DesignJet T2600 MFP Series	HP Inc.	HP DesignJet T1600 Printer Series; HP DesignJet T2600 MFP Series	Eletrônicos	0.00	1.50	Equipamento de imagem	\N	f	\N
f7f76da8-d1d0-513d-9448-610d0d0c34d8	HP Inc. HP DesignJet XL 3600 MFP Series	HP Inc.	HP DesignJet XL 3600 MFP Series	Eletrônicos	0.00	2.00	Equipamento de imagem	\N	f	\N
f8646dc0-f58c-5b6b-aab3-562c5197382c	KIP KIP 700	KIP	KIP 700	Eletrônicos	0.92	0.60	Equipamento de imagem	\N	f	\N
0089f143-81f5-5a62-a72b-d24a769040d8	SKS SKSIT3601GE	SKS	SKSIT3601GE	Eletrodomésticos	3.00	189.00	Fogão/Forno	\N	f	\N
05908834-27c8-597f-aea3-a3918717b3d8	LG LTEL7337*E	LG	LTEL7337*E	Eletrodomésticos	1.69	195.00	Fogão/Forno	\N	f	\N
08ccda81-94a4-5681-ab6e-89fdf067fa23	Midea MC-8F72A2H333UL	Midea	MC-8F72A2H333UL	Eletrodomésticos	2.51	188.00	Fogão/Forno	\N	f	\N
0ca0559b-4402-58b2-b3f4-b585f221ea44	Bosch HIS5657C	Bosch	HIS5657C	Eletrodomésticos	4.00	195.00	Fogão/Forno	\N	f	\N
72d13f8c-0e39-5dcd-9ef6-04576319057d	Bertazzoni MAS365INMXG	Bertazzoni	MAS365INMXG	Eletrodomésticos	1.00	187.00	Fogão/Forno	\N	f	\N
8b918d8a-efd6-580a-bf21-8bee9c60c59d	LG LSIL6332*E	LG	LSIL6332*E	Eletrodomésticos	3.00	189.00	Fogão/Forno	\N	f	\N
51f9ec7d-2ab3-5245-a7ef-31b47c6e478c	LG CBIU3639*E	LG	CBIU3639*E	Eletrodomésticos	5.00	189.00	Fogão/Forno	\N	f	\N
d7c7e78f-92cd-5f77-ae3f-35d69ceebffe	LG LDEL7324*E	LG	LDEL7324*E	Eletrodomésticos	2.00	195.00	Fogão/Forno	\N	f	\N
b869eeb2-3e79-51a3-84d6-9c1764e31cba	RCA 65D1	RCA	65D1	Eletrônicos	117.69	216.87	Televisão	\N	f	\N
b95fc09a-9d7d-58ee-b28b-57badd772f8a	Samsung QN83S85FAE	Samsung	QN83S85FAE	Eletrônicos	167.65	312.20	Televisão	\N	f	\N
bc172332-77cf-56de-bd4e-61ad0cfd7f06	LOEWE. stellar 55	LOEWE.	stellar 55	Eletrônicos	64.42	120.34	Televisão	\N	f	\N
bc82b8c1-d3d3-55c0-8099-3d7a9b7b5b4c	Sansui LE-32VA1	Sansui	LE-32VA1	Eletrônicos	35.64	67.19	Televisão	\N	f	\N
bf51a0f3-e532-59f5-a025-37e7312c6919	Sansui LE-75VA1	Sansui	LE-75VA1	Eletrônicos	148.56	273.48	Televisão	\N	f	\N
c1636d2e-371a-5381-ad30-794bbb4e46d5	Samsung QN77S95FAF	Samsung	QN77S95FAF	Eletrônicos	169.04	314.05	Televisão	\N	f	\N
c24aa614-edf3-539e-8f99-bfc2b0a8a315	Sansui LE-55TA1	Sansui	LE-55TA1	Eletrônicos	79.50	147.00	Televisão	\N	f	\N
d0459dcc-fddc-5801-8583-afa7c762a93b	Samsung QN75QN90DAF	Samsung	QN75QN90DAF	Eletrônicos	141.39	307.88	Televisão	\N	f	\N
d115650e-c12d-53cf-934b-b0e61e63d7fe	XITRIX XPN-DSA8650	XITRIX	XPN-DSA8650	Eletrônicos	166.52	306.05	Televisão	\N	f	\N
0a07f9ce-342f-5692-b8f1-11fb67f76bb9	Samsung QN43QN90DAF	Samsung	QN43QN90DAF	Eletrônicos	63.40	143.60	Televisão	\N	f	\N
00507739-daa3-5b3e-b0aa-abcb8d37fabc	Samsung QN48S90FAE	Samsung	QN48S90FAE	Eletrônicos	84.90	161.18	Televisão	\N	f	\N
040c45bf-e2b7-5682-8fca-1328a4a10a59	SANSUI, AMZFAST LE-32V1	SANSUI, AMZFAST	LE-32V1	Eletrônicos	34.76	65.59	Televisão	\N	f	\N
fb694018-ea92-5524-8051-1d6265615a84	LG CBEW3017*E	LG	CBEW3017*E	Eletrodomésticos	4.00	195.00	Fogão/Forno	\N	f	\N
5f2b90a7-df45-5ef8-8336-50086d82775b	Sansui LE-43V1	Sansui	LE-43V1	Eletrônicos	64.06	118.81	Televisão	\N	f	\N
60c5a0f3-492e-5178-aa66-911ba39b8d87	Samsung QN65S95HAF	Samsung	QN65S95HAF	Eletrônicos	125.24	234.00	Televisão	\N	f	\N
644347d6-8f2f-5d5f-aabc-7243a34c5de2	Samsung QN77S95DAF	Samsung	QN77S95DAF	Eletrônicos	167.33	360.80	Televisão	\N	f	\N
6b439300-324c-5b9e-a85c-4721801dc739	Sansui LE-55V4	Sansui	LE-55V4	Eletrônicos	72.52	134.85	Televisão	\N	f	\N
6fbdf19d-1d36-573c-a046-f78fad2dac0e	XITRIX XPN-DSA3250	XITRIX	XPN-DSA3250	Eletrônicos	34.40	64.37	Televisão	\N	f	\N
c7cb9f29-92aa-5e67-9a52-f35750f83c39	XITRIX XPN-DSA5850	XITRIX	XPN-DSA5850	Eletrônicos	100.90	186.15	Televisão	\N	f	\N
c7d673cc-a0e8-5bea-a751-ffe376ea9a58	Sansui LE-24VA1	Sansui	LE-24VA1	Eletrônicos	23.84	45.59	Televisão	\N	f	\N
cd2f3de5-2344-5702-9b72-febbf0386017	Samsung QN83S95FAE	Samsung	QN83S95FAE	Eletrônicos	215.22	399.01	Televisão	\N	f	\N
0f86c22b-d122-57fe-a3b1-481af0067470	Oce ColorWave 3500	Oce	ColorWave 3500	Eletrônicos	1.88	5.80	Equipamento de imagem	\N	f	\N
12c0aaec-b61a-5008-86b4-d2e6175438de	Oce ColorWave 700	Oce	ColorWave 700	Eletrônicos	1.88	5.80	Equipamento de imagem	\N	f	\N
12f975bd-f4d7-5edc-8df1-251d45aacbaa	Oce PlotWave 450 Printer	Oce	PlotWave 450 Printer	Eletrônicos	1.03	5.30	Equipamento de imagem	\N	f	\N
25954c68-3254-5814-94fa-4ddfd88b7ec1	Oce PlotWave 550 Printer	Oce	PlotWave 550 Printer	Eletrônicos	1.03	5.30	Equipamento de imagem	\N	f	\N
25b30afa-e987-5c61-a808-021efa553d51	Canon plotWave T55	Canon	plotWave T55	Eletrônicos	1.10	0.00	Equipamento de imagem	\N	f	\N
3480f3c0-dbaf-5f8c-b0b7-ad3c32c34232	Canon colorWave T65	Canon	colorWave T65	Eletrônicos	2.16	0.00	Equipamento de imagem	\N	f	\N
4c6b41a0-920e-59db-88a8-b404ba418996	Canon colorWave T60	Canon	colorWave T60	Eletrônicos	2.09	0.00	Equipamento de imagem	\N	f	\N
52fe5895-31e6-5c2e-8700-9450ca4c927b	Oce PlotWave 345  Printer	Oce	PlotWave 345  Printer	Eletrônicos	1.21	5.30	Equipamento de imagem	\N	f	\N
65efac4e-536d-5286-90c3-279e3231f2b5	Canon colorWave T65	Canon	colorWave T65	Eletrônicos	2.09	4.40	Equipamento de imagem	\N	f	\N
754ac400-de96-524e-ab12-2e20d9a0ad3d	Oce PlotWave 345  Multifunction Express	Oce	PlotWave 345  Multifunction Express	Eletrônicos	1.21	5.30	Equipamento de imagem	\N	f	\N
7648a4b2-3041-5526-beb5-77fb9b2e214a	Oce PlotWave 550 Multifunction Express	Oce	PlotWave 550 Multifunction Express	Eletrônicos	1.03	5.30	Equipamento de imagem	\N	f	\N
792deb9b-9879-546c-92f0-e9fdc728d271	Canon plotWave T35	Canon	plotWave T35	Eletrônicos	1.30	0.00	Equipamento de imagem	\N	f	\N
7ba6e680-add0-5492-a260-653baa7819af	Oce PlotWave 365  Multifunction Express	Oce	PlotWave 365  Multifunction Express	Eletrônicos	1.21	5.30	Equipamento de imagem	\N	f	\N
850975ad-188e-5b9e-bec2-8268d0638e4f	Canon plotWave T75	Canon	plotWave T75	Eletrônicos	1.40	0.00	Equipamento de imagem	\N	f	\N
8959217f-b116-566b-a5cf-28ce63fffcb5	Oce ColorWave 3700	Oce	ColorWave 3700	Eletrônicos	1.88	5.80	Equipamento de imagem	\N	f	\N
9ad3b943-6d27-5658-b4e8-d6222419157d	Canon colorWave T60	Canon	colorWave T60	Eletrônicos	2.16	0.00	Equipamento de imagem	\N	f	\N
9b4546ce-efb1-501a-8760-4b246e1161a1	Canon plotWave T50	Canon	plotWave T50	Eletrônicos	1.10	0.00	Equipamento de imagem	\N	f	\N
9c018830-f218-59ce-b553-d52f21cd9e5f	Oce ColorWave 3500	Oce	ColorWave 3500	Eletrônicos	1.88	5.80	Equipamento de imagem	\N	f	\N
9db3cac3-1ea1-54f4-97ad-cc32e66146b9	Canon plotWave T30	Canon	plotWave T30	Eletrônicos	1.14	0.00	Equipamento de imagem	\N	f	\N
b070f9d7-4dc7-5c9b-8dbe-f4ce75969832	Oce PlotWave 450 Multifunction Express	Oce	PlotWave 450 Multifunction Express	Eletrônicos	1.03	5.30	Equipamento de imagem	\N	f	\N
b8163f45-172a-582c-a2e5-1df55797d07c	Oce Oce VarioPrint 6330	Oce	Oce VarioPrint 6330	Eletrônicos	44.20	120.90	Equipamento de imagem	\N	f	\N
c3f532c2-2819-5761-b7fb-8daa4c93ff2f	Canon plotWave T30	Canon	plotWave T30	Eletrônicos	1.30	0.00	Equipamento de imagem	\N	f	\N
cbb00d68-6406-538d-80c1-ad7607813745	Oce Oce VarioPrint 6270	Oce	Oce VarioPrint 6270	Eletrônicos	44.20	106.30	Equipamento de imagem	\N	f	\N
cd999336-731d-59d8-9381-38a29832df31	Canon plotWave T75	Canon	plotWave T75	Eletrônicos	1.10	0.00	Equipamento de imagem	\N	f	\N
ce7d295c-5398-5881-8434-03d1a7b27c89	Oce ColorWave 700	Oce	ColorWave 700	Eletrônicos	1.88	5.80	Equipamento de imagem	\N	f	\N
d5628503-f416-5c9b-9c3b-5504261145d1	Canon plotWave T50	Canon	plotWave T50	Eletrônicos	1.40	0.00	Equipamento de imagem	\N	f	\N
d6e5d34f-6362-57ae-abb2-86ba6fa34429	Canon plotWave T35	Canon	plotWave T35	Eletrônicos	1.14	0.00	Equipamento de imagem	\N	f	\N
d7cae181-c111-5587-ab36-8405f3a63a9d	Oce ColorWave 500	Oce	ColorWave 500	Eletrônicos	1.88	5.80	Equipamento de imagem	\N	f	\N
eac0a2b1-96b2-5241-8af1-f7f7fc9e6b1b	Oce ColorWave 700	Oce	ColorWave 700	Eletrônicos	1.88	5.80	Equipamento de imagem	\N	f	\N
fb971b43-e747-5bc2-968d-662fd9b57c84	Oce PlotWave 365  Printer	Oce	PlotWave 365  Printer	Eletrônicos	1.21	5.30	Equipamento de imagem	\N	f	\N
05ec4922-1213-5346-bd05-7278b273d687	HP Inc. HP DesignJet T1700 Printer Series	HP Inc.	HP DesignJet T1700 Printer Series	Eletrônicos	0.27	1.50	Equipamento de imagem	\N	f	\N
0c2d413d-7ea4-57f6-bd96-da0dffdffdca	KIP KIP 970	KIP	KIP 970	Eletrônicos	3.38	1.20	Equipamento de imagem	\N	f	\N
165598ec-f91a-5e83-9694-ba99032d16fc	Konica Minolta AccurioPress C7100 + PF-712 [Printer System]	Konica Minolta	AccurioPress C7100 + PF-712 [Printer System]	Eletrônicos	121.80	21.41	Equipamento de imagem	\N	f	\N
1a699d12-27d9-5a61-978a-d9c899b64095	KIP KIP 7170	KIP	KIP 7170	Eletrônicos	6.35	1.10	Equipamento de imagem	\N	f	\N
1a9e5335-c74b-5fb2-b1eb-1aca99088c96	HP Inc. HP DesignJet Z9 Printer Series	HP Inc.	HP DesignJet Z9 Printer Series	Eletrônicos	0.34	1.40	Equipamento de imagem	\N	f	\N
1cc7555c-2646-5eb3-8c38-6101b2258f7c	Konica Minolta AccurioPress C12000 + PF-712 [Printer System]	Konica Minolta	AccurioPress C12000 + PF-712 [Printer System]	Eletrônicos	123.00	35.52	Equipamento de imagem	\N	f	\N
2b89f6a8-f6f0-518a-8a59-455ae21d5d4a	HP Inc. HP DesignJet T940 Printer Series	HP Inc.	HP DesignJet T940 Printer Series	Eletrônicos	0.00	1.50	Equipamento de imagem	\N	f	\N
2be495e8-e08b-5338-8d08-f0533b33222d	KIP KIP 7970	KIP	KIP 7970	Eletrônicos	2.70	1.60	Equipamento de imagem	\N	f	\N
398a43af-1a44-5a79-b336-52dcb433c510	KIP KIP 7570P	KIP	KIP 7570P	Eletrônicos	5.45	1.30	Equipamento de imagem	\N	f	\N
3c00c3cf-d99d-5541-a36a-32da1ed90050	HP Inc. HP HD Pro 2 42-in Scanner	HP Inc.	HP HD Pro 2 42-in Scanner	Eletrônicos	0.43	0.90	Equipamento de imagem	\N	f	\N
41f74d30-9596-5f8e-aff8-bb1edf261e33	Konica Minolta AccurioPress C14000 + PF-713 [MFP System]	Konica Minolta	AccurioPress C14000 + PF-713 [MFP System]	Eletrônicos	122.50	40.06	Equipamento de imagem	\N	f	\N
56c48e63-85c6-56f2-bfb5-57041e6c6444	Fujitsu N7100E	Fujitsu	N7100E	Eletrônicos	0.55	0.60	Equipamento de imagem	\N	f	\N
61743f68-ebae-54af-af78-aaac61aed732	KIP KIP 7570M	KIP	KIP 7570M	Eletrônicos	5.45	1.30	Equipamento de imagem	\N	f	\N
623d6ab8-c543-50eb-a218-7cb5dafbe2f3	Konica Minolta AccurioPress C14000 + PF-712 [Printer System]	Konica Minolta	AccurioPress C14000 + PF-712 [Printer System]	Eletrônicos	122.50	39.52	Equipamento de imagem	\N	f	\N
73ac782c-2292-5654-a064-a469f1f67573	HP Inc. HP SD Pro 2 44-in Scanner	HP Inc.	HP SD Pro 2 44-in Scanner	Eletrônicos	0.62	0.90	Equipamento de imagem	\N	f	\N
7dfae4ef-bc42-5529-a7d3-c4caf47f8b7e	Konica Minolta AccurioPress C12000 + PF-713 [MFP System]	Konica Minolta	AccurioPress C12000 + PF-713 [MFP System]	Eletrônicos	123.00	35.27	Equipamento de imagem	\N	f	\N
7ec1c024-e3da-5ab9-aea3-8f6c7ae75b2d	Konica Minolta AccurioPress C4080	Konica Minolta	AccurioPress C4080	Eletrônicos	33.10	8.60	Equipamento de imagem	\N	f	\N
80a78bc4-89dc-543e-b26d-846042a89eaa	Konica Minolta AccurioPress C4070	Konica Minolta	AccurioPress C4070	Eletrônicos	33.10	8.60	Equipamento de imagem	\N	f	\N
85331b11-7dc0-5433-9a28-a48494b5b4d4	KIP KIP 660	KIP	KIP 660	Eletrônicos	3.20	0.80	Equipamento de imagem	\N	f	\N
a82bf63b-f7f6-544b-8e7a-d3409dd90600	Konica Minolta AccurioPress C7100 + PF-713 [MFP System]	Konica Minolta	AccurioPress C7100 + PF-713 [MFP System]	Eletrônicos	121.80	21.58	Equipamento de imagem	\N	f	\N
ae19a0cb-1ceb-5186-81e3-15b70b292c89	Konica Minolta AccurioPress C7090 + PF-713 [MFP System]	Konica Minolta	AccurioPress C7090 + PF-713 [MFP System]	Eletrônicos	121.80	21.58	Equipamento de imagem	\N	f	\N
bde6956a-885c-51a7-a72c-79792e119c56	Konica Minolta AccurioPrint C4065	Konica Minolta	AccurioPrint C4065	Eletrônicos	33.10	8.60	Equipamento de imagem	\N	f	\N
cc3d781e-541f-565d-a95e-acea61e5803a	Fujitsu N7100EA	Fujitsu	N7100EA	Eletrônicos	0.55	0.60	Equipamento de imagem	\N	f	\N
d9cbfd1f-2cc7-5d0a-9d29-5bd3d2a64eb4	Konica Minolta AccurioPress C7090 + PF-712 [Printer System]	Konica Minolta	AccurioPress C7090 + PF-712 [Printer System]	Eletrônicos	121.80	21.41	Equipamento de imagem	\N	f	\N
dde4c3b7-5f5b-509a-a9c5-7db053f53eb1	HP Inc. HP DesignJet Z6 Printer Series	HP Inc.	HP DesignJet Z6 Printer Series	Eletrônicos	0.34	1.40	Equipamento de imagem	\N	f	\N
026c3fd5-d313-5694-82c0-18f77cc18eb6	Ricoh N7100EA	Ricoh	N7100EA	Eletrônicos	0.55	0.60	Equipamento de imagem	\N	f	\N
057e1aef-5c07-5d89-8f37-8ed071c95edd	Ricoh Pro C7210SX	Ricoh	Pro C7210SX	Eletrônicos	151.50	12.50	Equipamento de imagem	\N	f	\N
06542ca5-61a3-50fc-afc6-247ec40fa922	ROWE ROWE ColorPress i10L	ROWE	ROWE ColorPress i10L	Eletrônicos	1.81	1.00	Equipamento de imagem	\N	f	\N
535a0ca1-288d-52bb-ab40-2869cf9ad54f	Ricoh N7100E	Ricoh	N7100E	Eletrônicos	0.55	0.60	Equipamento de imagem	\N	f	\N
72ed47db-2c08-53fb-b1b5-2d2e740c0b91	ROWE ROWE ColorPress i8L with ROWE Scan 450i 36	ROWE	ROWE ColorPress i8L with ROWE Scan 450i 36	Eletrônicos	1.84	1.00	Equipamento de imagem	\N	f	\N
a5d18fa7-0f00-5100-88a4-0443a19993df	Ricoh IM C300F	Ricoh	IM C300F	Eletrônicos	0.00	0.37	Equipamento de imagem	\N	f	\N
b015d6f5-83ba-5c76-907d-8467b0523fc8	ROWE ROWE ColorPress i10L with ROWE Scan 450i 36	ROWE	ROWE ColorPress i10L with ROWE Scan 450i 36	Eletrônicos	1.84	1.00	Equipamento de imagem	\N	f	\N
b5986bfa-1c15-5ce7-a5da-c1cbbe5055d3	ROWE ROWE ColorPress i8L	ROWE	ROWE ColorPress i8L	Eletrônicos	1.81	1.00	Equipamento de imagem	\N	f	\N
b5b62285-b424-58bb-94f4-72fb166ccd76	Ricoh Pro C7210X	Ricoh	Pro C7210X	Eletrônicos	151.50	12.20	Equipamento de imagem	\N	f	\N
bcb6dcd6-1738-54bb-a6d9-068c6e0a3684	ROWE ROWE ColorPress i6	ROWE	ROWE ColorPress i6	Eletrônicos	1.81	1.00	Equipamento de imagem	\N	f	\N
d0726a64-11b7-5a66-94e6-634de0697ae8	Ricoh Pro C7200X	Ricoh	Pro C7200X	Eletrônicos	151.50	11.20	Equipamento de imagem	\N	f	\N
e74a7007-8979-50bd-a4e1-6579a46567f7	ROWE ROWE ColorPress i10 with ROWE Scan 450i 36	ROWE	ROWE ColorPress i10 with ROWE Scan 450i 36	Eletrônicos	1.84	1.00	Equipamento de imagem	\N	f	\N
e9626633-4373-5770-9c15-f746611398ee	ROWE ROWE ColorPress i8 with ROWE Scan 450i 36	ROWE	ROWE ColorPress i8 with ROWE Scan 450i 36	Eletrônicos	1.84	1.00	Equipamento de imagem	\N	f	\N
f4687b39-a454-5d5b-b5b8-630368bc66f3	ROWE ROWE ColorPress i10	ROWE	ROWE ColorPress i10	Eletrônicos	1.81	1.00	Equipamento de imagem	\N	f	\N
ff106564-84be-5333-a14f-d46e0f16962a	ROWE ROWE ColorPress i6 with ROWE Scan 450i 36	ROWE	ROWE ColorPress i6 with ROWE Scan 450i 36	Eletrônicos	1.84	1.00	Equipamento de imagem	\N	f	\N
ffaec5fa-4cef-5843-a0c6-b58781a536ca	ROWE ROWE ColorPress i8	ROWE	ROWE ColorPress i8	Eletrônicos	1.81	1.00	Equipamento de imagem	\N	f	\N
022b6365-d7ce-58d0-b3ce-be205f8a0151	LG LSIS6338*E	LG	LSIS6338*E	Eletrodomésticos	5.00	189.00	Fogão/Forno	\N	f	\N
0495e15b-09e9-5888-a8dc-53d3260fe7bc	LG CBIH3613*E	LG	CBIH3613*E	Eletrodomésticos	4.00	189.00	Fogão/Forno	\N	f	\N
1466a541-e9f8-50b3-b1f9-20ec55f40446	Samsung NSE80H63S*	Samsung	NSE80H63S*	Eletrodomésticos	2.00	195.00	Fogão/Forno	\N	f	\N
1964ff9f-6006-50eb-9a74-4fbf0f8dc898	LG CBIH3017*E	LG	CBIH3017*E	Eletrodomésticos	6.00	189.00	Fogão/Forno	\N	f	\N
1d1a7a94-2e87-5703-a96e-6b09d4dec65f	Samsung CC70*36***	Samsung	CC70*36***	Eletrodomésticos	7.81	195.00	Fogão/Forno	\N	f	\N
1da6006b-968e-577b-9a6d-1f3bf5809ef3	LG LREN6323*E	LG	LREN6323*E	Eletrodomésticos	1.42	195.00	Fogão/Forno	\N	f	\N
232c5fdc-5d65-54f8-95ce-978575e63a23	Bosch HIS8057C	Bosch	HIS8057C	Eletrodomésticos	5.00	195.00	Fogão/Forno	\N	f	\N
286b7816-40b6-5416-8602-7e473314c4ee	LG CBEW3013*E	LG	CBEW3013*E	Eletrodomésticos	4.01	195.00	Fogão/Forno	\N	f	\N
28d014e2-3ec6-5398-941c-773ad56d3f1d	Fotile Electric Ranges	Fotile	Electric Ranges	Eletrodomésticos	3.00	195.00	Fogão/Forno	\N	f	\N
2b274b96-205b-5920-bc55-87e0957feb03	LG LSIU6339*E	LG	LSIU6339*E	Eletrodomésticos	6.00	189.00	Fogão/Forno	\N	f	\N
34c4bdf5-3241-5d63-b1b0-d0ffc697d353	LG CBEW3617*E	LG	CBEW3617*E	Eletrodomésticos	4.00	195.00	Fogão/Forno	\N	f	\N
397e87ba-1658-5f56-8ecc-620cc58f4ec8	LG CBEW3613*E	LG	CBEW3613*E	Eletrodomésticos	3.98	195.00	Fogão/Forno	\N	f	\N
3ac866d8-035c-5e2d-8689-4a337aa291b9	Bertazzoni PE304INDXV	Bertazzoni	PE304INDXV	Eletrodomésticos	3.93	192.00	Fogão/Forno	\N	f	\N
3f2e8ae8-1afd-54ae-8102-6a6106c6ec14	Samsung NSE80H63X*	Samsung	NSE80H63X*	Eletrodomésticos	2.00	195.00	Fogão/Forno	\N	f	\N
3fee40b9-326d-5c85-aaab-0d9e11895077	Samsung NZ30*G5332**	Samsung	NZ30*G5332**	Eletrodomésticos	0.28	195.00	Fogão/Forno	\N	f	\N
41aa9537-e159-5fd1-83c8-2bb33f1ae533	LG LREN6325*E	LG	LREN6325*E	Eletrodomésticos	2.00	195.00	Fogão/Forno	\N	f	\N
478ecea7-8279-5f62-9351-31bedae16010	Bertazzoni PE365INDXV	Bertazzoni	PE365INDXV	Eletrodomésticos	2.90	190.00	Fogão/Forno	\N	f	\N
4a820434-fece-56bf-a9a8-2db7b9bec86b	Bertazzoni MAS365INMBG	Bertazzoni	MAS365INMBG	Eletrodomésticos	1.00	187.00	Fogão/Forno	\N	f	\N
4b5d4d7f-b5d7-58e5-b92d-7c44824c9417	Midea MC-9V96E0H378UL	Midea	MC-9V96E0H378UL	Eletrodomésticos	3.37	188.00	Fogão/Forno	\N	f	\N
52e886c5-1b47-50fc-a53c-75bac5b14c4f	LG LSIL6336*E	LG	LSIL6336*E	Eletrodomésticos	5.00	189.00	Fogão/Forno	\N	f	\N
550739cb-6846-53e3-a581-f67ddc647000	Samsung NE63F6711**	Samsung	NE63F6711**	Eletrodomésticos	1.89	195.00	Fogão/Forno	\N	f	\N
58989716-d489-5bea-8053-8dad85e3b622	Bertazzoni MAS304INMBG	Bertazzoni	MAS304INMBG	Eletrodomésticos	1.00	188.00	Fogão/Forno	\N	f	\N
5eeb836d-c46f-5df5-b715-b47775685e7a	LG LCE3010SBE	LG	LCE3010SBE	Eletrodomésticos	4.00	195.00	Fogão/Forno	\N	f	\N
66669dff-67e3-5b00-9116-6fcff51d66e5	LG LSIL633T*E	LG	LSIL633T*E	Eletrodomésticos	3.00	189.00	Fogão/Forno	\N	f	\N
69bbfce4-ea94-5a48-b8f3-69e670ca7c71	LG LSIL633C*E	LG	LSIL633C*E	Eletrodomésticos	3.00	189.00	Fogão/Forno	\N	f	\N
69df89ed-56f6-57c6-b2d1-c4eaac40daaa	LG LSEL633C*E	LG	LSEL633C*E	Eletrodomésticos	1.42	195.00	Fogão/Forno	\N	f	\N
6f38cde7-069c-510b-8689-c119e57cb470	Samsung NZ30*G6332**	Samsung	NZ30*G6332**	Eletrodomésticos	2.00	195.00	Fogão/Forno	\N	f	\N
72484c38-9ebf-546e-bc9b-15dc84a0e941	LG LTIS7338*E	LG	LTIS7338*E	Eletrodomésticos	6.00	189.00	Fogão/Forno	\N	f	\N
75be5107-a58d-5857-8274-e387fec09027	LG LREL6325*H	LG	LREL6325*H	Eletrodomésticos	2.00	195.00	Fogão/Forno	\N	f	\N
75cb751c-5160-5c50-9221-e2997c8dbef2	Midea MC-8F72E1H333UL-F	Midea	MC-8F72E1H333UL-F	Eletrodomésticos	3.44	188.00	Fogão/Forno	\N	f	\N
7a5c1b73-1b5b-5d07-9190-3164847cc1bc	LG LSEL6335*E	LG	LSEL6335*E	Eletrodomésticos	2.00	195.00	Fogão/Forno	\N	f	\N
7b695115-9a28-5a71-b4f9-5b308b3232ed	LG CBIU3039*E	LG	CBIU3039*E	Eletrodomésticos	6.00	189.00	Fogão/Forno	\N	f	\N
84332e17-d116-5825-9b7f-ba67abc8795d	LG LSEL6333*H	LG	LSEL6333*H	Eletrodomésticos	1.42	195.00	Fogão/Forno	\N	f	\N
8655051e-51ac-5401-a349-e74e54829456	LG LCE3610SBE	LG	LCE3610SBE	Eletrodomésticos	4.00	195.00	Fogão/Forno	\N	f	\N
86e66be0-3fef-5d62-981a-94ba2dffca35	LG CBIH3013*E	LG	CBIH3013*E	Eletrodomésticos	4.00	189.00	Fogão/Forno	\N	f	\N
90cac3ad-6e54-5fd2-aa84-c8ec92dc05be	Bertazzoni MAS304INMXG	Bertazzoni	MAS304INMXG	Eletrodomésticos	1.00	188.00	Fogão/Forno	\N	f	\N
92c35c63-b9f8-5dce-ac47-6cf6530377d6	LG LSIL6334*E	LG	LSIL6334*E	Eletrodomésticos	4.00	189.00	Fogão/Forno	\N	f	\N
9ca1dc12-e02d-5a8b-9694-5d50e748c705	LG CBIS3018*E	LG	CBIS3018*E	Eletrodomésticos	6.00	189.00	Fogão/Forno	\N	f	\N
9d31cc9b-d945-5e7d-b35f-f2c98a44e8f0	Samsung NE63D6511**	Samsung	NE63D6511**	Eletrodomésticos	1.90	195.00	Fogão/Forno	\N	f	\N
9e1bfda3-4081-5a0a-8d0b-cb371273dbf7	Samsung NSE90H63S*	Samsung	NSE90H63S*	Eletrodomésticos	1.80	195.00	Fogão/Forno	\N	f	\N
a0b34992-1045-5700-97b6-983b831cdebe	LG LRIN6323*E	LG	LRIN6323*E	Eletrodomésticos	4.00	189.00	Fogão/Forno	\N	f	\N
a22c887a-c89b-5833-bb2f-3fa8b4249f28	LG LSIU6338*E	LG	LSIU6338*E	Eletrodomésticos	6.00	189.00	Fogão/Forno	\N	f	\N
a7dbed2c-a122-5472-a05f-b7a327f0d554	LG CBIS3618*E	LG	CBIS3618*E	Eletrodomésticos	5.00	189.00	Fogão/Forno	\N	f	\N
aa9f8499-88a2-5bdf-bee8-9da48f44f448	Ikea MC-8F72A2H333UL	Ikea	MC-8F72A2H333UL	Eletrodomésticos	2.75	188.00	Fogão/Forno	\N	f	\N
ad2b852a-c97d-5756-96c8-a74f48fcd962	Samsung NSE70H63S*	Samsung	NSE70H63S*	Eletrodomésticos	1.97	195.00	Fogão/Forno	\N	f	\N
b0459936-91e0-500a-88e2-e1b89ff04b60	LG LSEL6333*E	LG	LSEL6333*E	Eletrodomésticos	1.42	195.00	Fogão/Forno	\N	f	\N
b2e17458-91eb-5288-bcfd-1f57bbd66fe9	Ikea MC-8F72A2H385UL	Ikea	MC-8F72A2H385UL	Eletrodomésticos	2.65	175.00	Fogão/Forno	\N	f	\N
b338bc06-0382-5644-9bd8-73886bdeab17	Samsung NZ36*G6432**	Samsung	NZ36*G6432**	Eletrodomésticos	3.00	195.00	Fogão/Forno	\N	f	\N
b4a8463f-850c-568a-8f01-2406ce6adfbe	LG LSEL6330*E	LG	LSEL6330*E	Eletrodomésticos	0.00	195.00	Fogão/Forno	\N	f	\N
b6d71548-d553-5c22-bb06-acaae1ee29f3	Samsung NSE6D*8702**	Samsung	NSE6D*8702**	Eletrodomésticos	1.37	195.00	Fogão/Forno	\N	f	\N
bc738d2b-c4f6-51c1-a25c-534c526c2709	Samsung NZ36*G5332**	Samsung	NZ36*G5332**	Eletrodomésticos	0.28	195.00	Fogão/Forno	\N	f	\N
c523d0b0-bf76-5e64-b600-6e8c5195d7b0	SKS SKSIR360IS	SKS	SKSIR360IS	Eletrodomésticos	4.39	189.00	Fogão/Forno	\N	f	\N
c8714eba-b068-559e-80c1-d957e3407fc6	Samsung NE63F6511**	Samsung	NE63F6511**	Eletrodomésticos	1.90	195.00	Fogão/Forno	\N	f	\N
c878b4c9-063c-5247-ba6c-542a4399077e	LG LREN6321*E	LG	LREN6321*E	Eletrodomésticos	1.42	195.00	Fogão/Forno	\N	f	\N
c87d07f8-f344-5dac-8be6-6a3740043284	Samsung NSE6D*8502**	Samsung	NSE6D*8502**	Eletrodomésticos	1.37	195.00	Fogão/Forno	\N	f	\N
cd2f57c4-9367-55ec-bebe-0240ed495f0d	LG LSEL6335LE	LG	LSEL6335LE	Eletrodomésticos	2.00	195.00	Fogão/Forno	\N	f	\N
d9b753a6-7bd3-55f1-9194-1e47c1d6c9f8	Dacor DOP30*940I*	Dacor	DOP30*940I*	Eletrodomésticos	3.12	195.00	Fogão/Forno	\N	f	\N
e2ce2a47-4973-53ed-abc3-a494cdb96397	Samsung NSE6D*8550**	Samsung	NSE6D*8550**	Eletrodomésticos	1.37	195.00	Fogão/Forno	\N	f	\N
e2cf6c9b-1a17-5c87-9d63-e92295a51b3b	LG LSEL6337*E	LG	LSEL6337*E	Eletrodomésticos	1.69	195.00	Fogão/Forno	\N	f	\N
e504dba6-6b84-5660-827d-7743c9e018ca	Samsung NE63D6711**	Samsung	NE63D6711**	Eletrodomésticos	1.89	195.00	Fogão/Forno	\N	f	\N
e687647e-cee5-5f6a-89c2-11c908b7be31	Bertazzoni MAS365INMNG	Bertazzoni	MAS365INMNG	Eletrodomésticos	1.00	187.00	Fogão/Forno	\N	f	\N
ea681c3b-9b69-5b98-b0c1-0c364a4639c1	LG CBIH3617*E	LG	CBIH3617*E	Eletrodomésticos	5.00	190.00	Fogão/Forno	\N	f	\N
eb15601a-7a6d-5493-bc11-3cbd94f0e96b	Ikea MC-9V96E0H378UL	Ikea	MC-9V96E0H378UL	Eletrodomésticos	3.41	188.00	Fogão/Forno	\N	f	\N
eb531bbe-8f72-5e33-9c34-d3ccdaa8d2de	Bertazzoni MAS304INMNG	Bertazzoni	MAS304INMNG	Eletrodomésticos	1.00	188.00	Fogão/Forno	\N	f	\N
eda06777-1ca8-5d14-9937-80e5926d341f	Midea MC-9V96E1H378UL	Midea	MC-9V96E1H378UL	Eletrodomésticos	3.70	188.00	Fogão/Forno	\N	f	\N
ef7b6029-df37-5b47-820d-33fefd5e5375	Samsung CC70*30***	Samsung	CC70*30***	Eletrodomésticos	8.35	195.00	Fogão/Forno	\N	f	\N
eff7d6d7-7d36-5304-bc9e-9a6bb8720875	Bertazzoni PE244INDXV	Bertazzoni	PE244INDXV	Eletrodomésticos	4.78	190.00	Fogão/Forno	\N	f	\N
f17d4b40-d9c3-5a0c-9179-cb0040b6218d	SKS SKSIT3001GE	SKS	SKSIT3001GE	Eletrodomésticos	5.00	189.00	Fogão/Forno	\N	f	\N
f22c18af-b684-5bcc-a74b-efecb98b2844	Samsung NSE90H63D*	Samsung	NSE90H63D*	Eletrodomésticos	1.80	195.00	Fogão/Forno	\N	f	\N
f4cdca43-fd06-5e0b-b159-c85d6600b222	Signature Kitchen Suite or SKS SKSIT3611GE	Signature Kitchen Suite or SKS	SKSIT3611GE	Eletrodomésticos	3.00	189.00	Fogão/Forno	\N	f	\N
0432290b-5543-5ba2-9774-eeff6f6361f9	Sansui LE-32KA1	Sansui	LE-32KA1	Eletrônicos	27.24	51.59	Televisão	\N	f	\N
05ef8d92-09e7-51a7-a31f-0a70383d54e5	Sansui LE-43KA1	Sansui	LE-43KA1	Eletrônicos	45.14	82.16	Televisão	\N	f	\N
112c12fb-3b18-5c82-b5ba-82066cf8e5d1	Samsung QN65S90FAF	Samsung	QN65S90FAF	Eletrônicos	131.59	246.40	Televisão	\N	f	\N
15fccfa9-c9bc-50a8-92ae-af0b991f3cc5	Samsung QN55S84FAF	Samsung	QN55S84FAF	Eletrônicos	86.03	180.84	Televisão	\N	f	\N
1b64b020-9ffe-5e97-898a-822b8a843fbe	Sansui LE-50V1	Sansui	LE-50V1	Eletrônicos	61.72	134.85	Televisão	\N	f	\N
1d5d77b8-1418-56b6-b60e-73f694f6796d	Loewe stellar 42	Loewe	stellar 42	Eletrônicos	57.23	106.67	Televisão	\N	f	\N
1ed7bc7b-27b4-5f6a-8a6d-3a2276f6f81e	SCEPTRE X322BV-SRDD	SCEPTRE	X322BV-SRDD	Eletrônicos	31.07	59.76	Televisão	\N	f	\N
24103558-b2ba-5346-a0a0-1f19c5925186	Samsung QN55S95FAF	Samsung	QN55S95FAF	Eletrônicos	113.60	211.48	Televisão	\N	f	\N
25847209-1406-5164-a0ad-af6131f7d864	Samsung QN65QN90FAF	Samsung	QN65QN90FAF	Eletrônicos	125.93	234.67	Televisão	\N	f	\N
25d7cd3a-2c31-5f23-8d81-d08fcaf73a21	Samsung QN65QN90DAF	Samsung	QN65QN90DAF	Eletrônicos	121.96	265.90	Televisão	\N	f	\N
2acf7531-e9ad-5b77-9398-6984f2bbd90a	Samsung QN77S90FAF	Samsung	QN77S90FAF	Eletrônicos	154.71	286.50	Televisão	\N	f	\N
2c707612-9524-5bab-9c7d-c0b39d3dcc5f	Samsung QN75QN95DAF	Samsung	QN75QN95DAF	Eletrônicos	148.20	320.70	Televisão	\N	f	\N
3b43cfec-401a-5106-97da-5839ed3c341a	Samsung QN55S90FAF	Samsung	QN55S90FAF	Eletrônicos	98.73	186.41	Televisão	\N	f	\N
3be42e9b-38c6-5f68-a91a-d083695b3561	Samsung QN65S95DAF	Samsung	QN65S95DAF	Eletrônicos	127.39	276.90	Televisão	\N	f	\N
3d791408-0905-5c39-854e-367cd899daac	Sansui LE-50TA1	Sansui	LE-50TA1	Eletrônicos	70.02	129.24	Televisão	\N	f	\N
4295a565-5705-5c26-b654-a52617655612	Sansui S40KAFT	Sansui	S40KAFT	Eletrônicos	46.63	85.55	Televisão	\N	f	\N
46985446-8ef9-5dcd-9e46-e170342d5263	XITRIX XPN-DSA6560	XITRIX	XPN-DSA6560	Eletrônicos	87.12	161.35	Televisão	\N	f	\N
46e1d899-655e-5986-b608-1a52b5a6f729	Sansui LE-40TA1	Sansui	LE-40TA1	Eletrônicos	54.85	103.50	Televisão	\N	f	\N
491b713c-f42e-5bfb-94f7-fbd2cda30cfe	Sansui LE-55VO	Sansui	LE-55VO	Eletrônicos	86.67	160.50	Televisão	\N	f	\N
58824b0f-9127-54cf-93e5-96fb7469b4b5	Samsung QN115QN90FF	Samsung	QN115QN90FF	Eletrônicos	343.50	631.05	Televisão	\N	f	\N
72caa0db-5134-510a-9e05-ab67f90a2a5c	SANSUI. LE-85TE1	SANSUI.	LE-85TE1	Eletrônicos	188.80	347.06	Televisão	\N	f	\N
7699227a-1805-5e96-8841-63cc787c009d	Samsung QN50QN90DAF	Samsung	QN50QN90DAF	Eletrônicos	74.27	165.50	Televisão	\N	f	\N
76fd410d-708a-5064-9815-e604be27d817	SANSUI, AMZFAST LE-24TA1	SANSUI, AMZFAST	LE-24TA1	Eletrônicos	24.32	46.73	Televisão	\N	f	\N
8268f81f-8f84-5d7f-8689-7ab06a834cf2	Sansui S32KAHT	Sansui	S32KAHT	Eletrônicos	30.15	60.92	Televisão	\N	f	\N
86bf58cd-2ae6-5ac9-ac30-c98328a3ce70	Samsung QN65S85FAF	Samsung	QN65S85FAF	Eletrônicos	114.17	213.90	Televisão	\N	f	\N
8a7dd62c-1508-5e26-a4db-bc52e290b922	Samsung QN55S95DAF	Samsung	QN55S95DAF	Eletrônicos	112.43	245.80	Televisão	\N	f	\N
942ea48a-b842-5f86-9711-49d04907437f	Samsung QN98QN90FAF	Samsung	QN98QN90FAF	Eletrônicos	193.08	357.22	Televisão	\N	f	\N
98327b1f-0cf2-5112-9041-fc0c80371de2	Samsung QN55QN90FAF	Samsung	QN55QN90FAF	Eletrônicos	102.38	193.09	Televisão	\N	f	\N
99a4363d-9c78-5109-b31c-25b52599a14c	Samsung QN43QN90FAF	Samsung	QN43QN90FAF	Eletrônicos	62.80	118.79	Televisão	\N	f	\N
9d505e5c-9248-52b8-b0c3-0a9e0f375214	Samsung QN77S90DAF	Samsung	QN77S90DAF	Eletrônicos	160.93	297.90	Televisão	\N	f	\N
a0f8db11-e41b-50dd-9eca-ffba4b470834	Sansui LE-50VA1	Sansui	LE-50VA1	Eletrônicos	68.37	126.94	Televisão	\N	f	\N
a8c76087-a833-58af-b0b9-d5edc22fa793	Samsung QN55S95HAF	Samsung	QN55S95HAF	Eletrônicos	107.58	202.00	Televisão	\N	f	\N
a9ff9dd4-285b-5fa4-bd5b-e8da217cfe06	Sansui LE-75VH5	Sansui	LE-75VH5	Eletrônicos	119.51	220.19	Televisão	\N	f	\N
ae0fb2e7-972c-5cb4-93fe-92956b953dcb	Samsung QN85QN90DAF	Samsung	QN85QN90DAF	Eletrônicos	181.05	390.00	Televisão	\N	f	\N
af2b9cf5-beb4-5c49-a89a-ef32be61c93d	LOEWE. stellar 65	LOEWE.	stellar 65	Eletrônicos	84.55	157.08	Televisão	\N	f	\N
b44d4b8a-0c4d-509b-b3fb-7a7799901f66	Sansui LE-65KA1	Sansui	LE-65KA1	Eletrônicos	102.25	189.00	Televisão	\N	f	\N
b4688573-7e26-5b45-8436-6705198bd844	Sansui LE-24T1	Sansui	LE-24T1	Eletrônicos	23.65	45.20	Televisão	\N	f	\N
b47ad1ec-5698-5ebc-860d-a10293c8b9a2	Samsung QN85QN90FAF	Samsung	QN85QN90FAF	Eletrônicos	186.31	344.87	Televisão	\N	f	\N
dfefd206-07fc-5770-a27e-052d83bab7a1	Samsung QN50QN90FAF	Samsung	QN50QN90FAF	Eletrônicos	75.76	143.81	Televisão	\N	f	\N
e1b404de-8be4-5a9a-a0fe-db911c733f6a	Samsung QN75QN90CAF	Samsung	QN75QN90CAF	Eletrônicos	138.97	183.80	Televisão	\N	f	\N
e242492b-872e-5980-be9f-b751015964ff	Samsung QN65S90DAF	Samsung	QN65S90DAF	Eletrônicos	134.53	251.10	Televisão	\N	f	\N
e28256e1-4ab5-580b-8573-82a50be52c05	Samsung QN65QN95DAF	Samsung	QN65QN95DAF	Eletrônicos	125.73	275.00	Televisão	\N	f	\N
e4a95e61-b8d7-557c-b8e2-2c6509d9f23d	Loewe stellar 48	Loewe	stellar 48	Eletrônicos	73.81	136.92	Televisão	\N	f	\N
e5f91755-2cf0-5b16-8c3c-b33927dcdac3	Sansui LE-32T1	Sansui	LE-32T1	Eletrônicos	28.40	54.00	Televisão	\N	f	\N
e9754864-aebc-5385-aaec-8548bdb73e82	Sansui LE-40VA1	Sansui	LE-40VA1	Eletrônicos	68.37	126.94	Televisão	\N	f	\N
ea19ea88-40a3-56ae-93e6-42c410783aaa	Sansui LE-43VA1	Sansui	LE-43VA1	Eletrônicos	53.32	99.24	Televisão	\N	f	\N
ec676326-b182-5603-99f4-a9e4d6ed0520	Sansui LE-50KA1	Sansui	LE-50KA1	Eletrônicos	67.97	126.82	Televisão	\N	f	\N
ed2e0ee6-47e9-59bd-90ec-fd5cb56d449d	Samsung QN65S95FAF	Samsung	QN65S95FAF	Eletrônicos	126.78	236.91	Televisão	\N	f	\N
f0386c94-e6fa-57d7-90c1-7c1123ede95a	Samsung QN42S90FAE	Samsung	QN42S90FAE	Eletrônicos	71.93	137.50	Televisão	\N	f	\N
f06d6d1b-ce77-593e-a5dc-497992c4e383	XITRIX XPN-DSA6550	XITRIX	XPN-DSA6550	Eletrônicos	102.78	189.72	Televisão	\N	f	\N
f16a8586-1dc1-5b11-b00d-b202660af080	Samsung QN75QN90FAF	Samsung	QN75QN90FAF	Eletrônicos	144.02	267.69	Televisão	\N	f	\N
f26895e6-3932-5e95-b74a-833b91a5e6a3	Samsung QN85QN95DAF	Samsung	QN85QN95DAF	Eletrônicos	192.53	413.70	Televisão	\N	f	\N
f2b8a878-e7c0-50f8-ae8c-0ee36848b19f	Samsung QN55S85FAF	Samsung	QN55S85FAF	Eletrônicos	96.48	180.24	Televisão	\N	f	\N
f94935a8-3997-55b1-a7ef-0fb69441fb21	XITRIX XPN-DSA5550	XITRIX	XPN-DSA5550	Eletrônicos	83.92	155.23	Televisão	\N	f	\N
fb60ce8e-ef0e-516f-89bd-cd57cc7c0d64	Samsung QN55QN90DAF	Samsung	QN55QN90DAF	Eletrônicos	102.15	223.90	Televisão	\N	f	\N
fc39b502-d0a5-5d53-a171-0865f45d8c92	Sansui LE-65V1	Sansui	LE-65V1	Eletrônicos	127.87	235.44	Televisão	\N	f	\N
fd482902-6e3c-5581-a018-90be3dd2bf12	Samsung QN55S90DAF	Samsung	QN55S90DAF	Eletrônicos	98.58	184.10	Televisão	\N	f	\N
0f11d15f-0f7a-5965-9123-a465abfcc20a	Servidor	\N	\N	Informática	60.00	\N	Servidor	\N	f	\N
23542654-6769-58e6-9a8e-c8708d8238ff	Chapa comercial	\N	\N	Cozinha	1200.00	\N	Chapa comercial	\N	f	\N
32bc0326-7d0a-5a00-9753-fd6f5f31723e	Lâmpada	\N	\N	Iluminação	123.90	\N	Lâmpada	\N	f	\N
37d947f0-88cc-55f1-be5b-d59977d45976	Freezer	\N	\N	Eletrodomésticos	125.00	\N	Freezer	\N	f	\N
3c56d755-1b37-5487-a95a-1882b9a6df57	Fogão/Forno	\N	\N	Eletrodomésticos	1290.00	\N	Fogão/Forno	\N	f	\N
44b15223-7bec-5d67-8fac-db985e3e01c5	Computador	\N	\N	Informática	96.67	\N	Computador	\N	f	\N
6f44b722-7cc0-51a6-8204-0ed72691b38b	Fornalha	\N	\N	Eletrodomésticos	5400.00	\N	Fornalha	\N	f	\N
716745a9-712e-5f8c-9d3e-e809fe240b42	Não categorizado	\N	\N	Outros	913.03	\N	Não categorizado	\N	f	\N
780845d2-b097-5576-812c-7e4f3a667900	Purificador de ar	\N	\N	Climatização	50.00	\N	Purificador de ar	\N	f	\N
8158deed-5e4c-55db-9f8f-cfbedbe6c2eb	Bomba de calor	\N	\N	Climatização	2387.50	\N	Bomba de calor	\N	f	\N
b03224d6-390e-55a5-9ea8-93d8f62bc65c	Geladeira	\N	\N	Eletrodomésticos	150.00	\N	Geladeira	\N	f	\N
b04ab192-7d35-522e-a8fe-0b7413e719d9	Equipamento de imagem	\N	\N	Eletrônicos	325.00	\N	Equipamento de imagem	\N	f	\N
b0a058f4-cfe7-5882-a355-0c0298f5ec68	Fritadeira comercial	\N	\N	Cozinha	1600.00	\N	Fritadeira comercial	\N	f	\N
b474827c-81b2-56d8-8508-786ca0b7c60a	Cafeteira comercial	\N	\N	Cozinha	900.00	\N	Cafeteira comercial	\N	f	\N
b833c7d7-cc49-5b11-9be3-f541aa8ec840	Ventilador/Exaustor	\N	\N	Climatização	154.17	\N	Ventilador/Exaustor	\N	f	\N
b9d0e8a2-95d9-5ec9-916b-a71cc0771ea8	Bomba de piscina	\N	\N	Eletrodomésticos	1100.00	\N	Bomba de piscina	\N	f	\N
be389ae9-2387-5726-a7df-feeda9b2e4c4	Aquecedor de água	\N	\N	Eletrodomésticos	11000.00	\N	Aquecedor de água	\N	f	\N
c0370d52-4de7-5c54-9a84-f38230f1ef98	Lava-louças	\N	\N	Eletrodomésticos	1800.00	\N	Lava-louças	\N	f	\N
d8ca8c39-31f2-5c42-9f71-6765892d24ac	Secadora	\N	\N	Eletrodomésticos	1600.00	\N	Secadora	\N	f	\N
e30e84bf-b862-5728-8ad3-c6c70a5e50d4	Desumidificador	\N	\N	Eletrodomésticos	500.00	\N	Desumidificador	\N	f	\N
17ec2033-1274-587c-9c08-03f16e660662	Frigobar	\N	\N	Eletrodomésticos	\N	185.34	Frigobar	\N	f	\N
a869831f-0baa-5dcf-acf7-29b5bb7baeaf	Congelador	\N	\N	Eletrodomésticos	\N	476.61	Congelador	\N	f	\N
\.


--
-- Data for Name: product_source_observation; Type: TABLE DATA; Schema: public; Owner: neondb_owner
--

COPY public.product_source_observation (id, canonical_product_id, source, external_id, brand, model, dataset_id, power_w, annual_energy_kwh, standby_power_w, observed_at, is_generic, voltage_raw, voltage_kind, voltage_min_v, voltage_max_v, raw_energy_value, raw_energy_unit) FROM stdin;
00f1430b-64be-5956-804d-7fc34ed6a17f	716745a9-712e-5f8c-9d3e-e809fe240b42	WATTSIMPLE	Baseboard heater (6 ft)	\N	\N	WATTSIMPLE	1500.0	\N	\N	2026-09-09 22:14:32.06663+00	f	\N	unknown	\N	\N	\N	\N
03001cec-867f-528e-903e-8ad07801d6c1	716745a9-712e-5f8c-9d3e-e809fe240b42	WATTSIMPLE	Hot tub	\N	\N	WATTSIMPLE	4000.0	\N	\N	2026-09-09 22:14:32.06663+00	f	\N	unknown	\N	\N	\N	\N
052c5160-0a95-5ea0-809f-3f147499c253	b0a058f4-cfe7-5882-a355-0c0298f5ec68	WATTSIMPLE	Deep fryer	\N	\N	WATTSIMPLE	1700.0	\N	\N	2026-09-09 22:14:32.06663+00	f	\N	unknown	\N	\N	\N	\N
0ac85898-5949-5039-b845-89265104240e	b833c7d7-cc49-5b11-9be3-f541aa8ec840	WATTSIMPLE	Bathroom exhaust fan	\N	\N	WATTSIMPLE	30.0	\N	\N	2026-09-09 22:14:32.06663+00	f	\N	unknown	\N	\N	\N	\N
0ce5f899-35fe-553c-93b9-a619ee614f40	716745a9-712e-5f8c-9d3e-e809fe240b42	WATTSIMPLE	Shop vac	\N	\N	WATTSIMPLE	1400.0	\N	\N	2026-09-09 22:14:32.06663+00	f	\N	unknown	\N	\N	\N	\N
0fbc9b12-d5fc-50b0-a4f7-ce2bc62a3884	716745a9-712e-5f8c-9d3e-e809fe240b42	WATTSIMPLE	Clothes iron	\N	\N	WATTSIMPLE	1100.0	\N	\N	2026-09-09 22:14:32.06663+00	f	\N	unknown	\N	\N	\N	\N
13857b56-adda-5af4-8216-2d8df50d5f9b	44b15223-7bec-5d67-8fac-db985e3e01c5	WATTSIMPLE	Desktop computer	\N	\N	WATTSIMPLE	200.0	\N	\N	2026-09-09 22:14:32.06663+00	f	\N	unknown	\N	\N	\N	\N
14cab248-7cf1-535a-8a54-6ec0da1db54d	716745a9-712e-5f8c-9d3e-e809fe240b42	WATTSIMPLE	Pond pump	\N	\N	WATTSIMPLE	150.0	\N	\N	2026-09-09 22:14:32.06663+00	f	\N	unknown	\N	\N	\N	\N
15a12160-61de-514d-b847-57aa6f13ecc9	716745a9-712e-5f8c-9d3e-e809fe240b42	WATTSIMPLE	Garage door opener	\N	\N	WATTSIMPLE	550.0	\N	\N	2026-09-09 22:14:32.06663+00	f	\N	unknown	\N	\N	\N	\N
15c37afe-ccca-5bec-9e52-5c4ad632b7ba	32bc0326-7d0a-5a00-9753-fd6f5f31723e	WATTSIMPLE	Christmas lights (LED, 500 count)	\N	\N	WATTSIMPLE	30.0	\N	\N	2026-09-09 22:14:32.06663+00	f	\N	unknown	\N	\N	\N	\N
1644dad5-0930-5f08-9e20-1b8e4689005d	32bc0326-7d0a-5a00-9753-fd6f5f31723e	WATTSIMPLE	LED bulb	\N	\N	WATTSIMPLE	10.0	\N	\N	2026-09-09 22:14:32.06663+00	f	\N	unknown	\N	\N	\N	\N
1a805893-d1f7-51c2-a11a-544660e4c268	be389ae9-2387-5726-a7df-feeda9b2e4c4	WATTSIMPLE	Electric water heater	\N	\N	WATTSIMPLE	4000.0	\N	\N	2026-09-09 22:14:32.06663+00	f	\N	unknown	\N	\N	\N	\N
1adaa03a-86a4-59fc-af0a-dd68600a0db7	3c56d755-1b37-5487-a95a-1882b9a6df57	WATTSIMPLE	Induction cooktop (single burner)	\N	\N	WATTSIMPLE	1800.0	\N	\N	2026-09-09 22:14:32.06663+00	f	\N	unknown	\N	\N	\N	\N
1d1d86f3-8809-5eb9-b44a-c397d6201e9d	716745a9-712e-5f8c-9d3e-e809fe240b42	WATTSIMPLE	Space heater	\N	\N	WATTSIMPLE	1500.0	\N	\N	2026-09-09 22:14:32.06663+00	f	\N	unknown	\N	\N	\N	\N
1e9e3421-5f1c-5cbd-8a6f-4161485ffcb8	b833c7d7-cc49-5b11-9be3-f541aa8ec840	WATTSIMPLE	Ceiling fan	\N	\N	WATTSIMPLE	60.0	\N	\N	2026-09-09 22:14:32.06663+00	f	\N	unknown	\N	\N	\N	\N
21d0918a-3f32-584d-933a-1c09d6cac5f7	716745a9-712e-5f8c-9d3e-e809fe240b42	WATTSIMPLE	Mobility scooter charger	\N	\N	WATTSIMPLE	100.0	\N	\N	2026-09-09 22:14:32.06663+00	f	\N	unknown	\N	\N	\N	\N
2271c429-2095-5f9d-a6af-5186ad39312f	716745a9-712e-5f8c-9d3e-e809fe240b42	WATTSIMPLE	CPAP machine	\N	\N	WATTSIMPLE	40.0	\N	\N	2026-09-09 22:14:32.06663+00	f	\N	unknown	\N	\N	\N	\N
2498cbdd-9d09-5e4f-a4f6-e190809c0ad3	3c56d755-1b37-5487-a95a-1882b9a6df57	WATTSIMPLE	Toaster oven	\N	\N	WATTSIMPLE	1200.0	\N	\N	2026-09-09 22:14:32.06663+00	f	\N	unknown	\N	\N	\N	\N
24bd3dfa-71fb-553e-b427-eab94ed65533	716745a9-712e-5f8c-9d3e-e809fe240b42	WATTSIMPLE	Bread maker	\N	\N	WATTSIMPLE	600.0	\N	\N	2026-09-09 22:14:32.06663+00	f	\N	unknown	\N	\N	\N	\N
25ad42f3-33a7-5c82-88aa-b677ca232583	716745a9-712e-5f8c-9d3e-e809fe240b42	WATTSIMPLE	Wine fridge	\N	\N	WATTSIMPLE	100.0	\N	\N	2026-09-09 22:14:32.06663+00	f	\N	unknown	\N	\N	\N	\N
26b0b6a5-0256-5801-bc75-5bd06e0017d5	716745a9-712e-5f8c-9d3e-e809fe240b42	WATTSIMPLE	Electric kettle	\N	\N	WATTSIMPLE	1500.0	\N	\N	2026-09-09 22:14:32.06663+00	f	\N	unknown	\N	\N	\N	\N
28ea6d87-816c-5e3e-8635-ae50f19477d4	716745a9-712e-5f8c-9d3e-e809fe240b42	WATTSIMPLE	LED TV (65")	\N	\N	WATTSIMPLE	100.0	\N	\N	2026-09-09 22:14:32.06663+00	f	\N	unknown	\N	\N	\N	\N
314a45c0-aa5a-56be-8e19-08c9ec74b21a	716745a9-712e-5f8c-9d3e-e809fe240b42	WATTSIMPLE	White noise machine	\N	\N	WATTSIMPLE	5.0	\N	\N	2026-09-09 22:14:32.06663+00	f	\N	unknown	\N	\N	\N	\N
3222078f-c462-515e-8774-1631c20e6d66	716745a9-712e-5f8c-9d3e-e809fe240b42	WATTSIMPLE	Microwave	\N	\N	WATTSIMPLE	1000.0	\N	\N	2026-09-09 22:14:32.06663+00	f	\N	unknown	\N	\N	\N	\N
345f0f89-a3aa-58ea-b596-90dd2e035c16	716745a9-712e-5f8c-9d3e-e809fe240b42	WATTSIMPLE	Well pump (1/2 HP)	\N	\N	WATTSIMPLE	1000.0	\N	\N	2026-09-09 22:14:32.06663+00	f	\N	unknown	\N	\N	\N	\N
34eadeae-75c4-5da5-bf0b-75a7dbb8a8a0	716745a9-712e-5f8c-9d3e-e809fe240b42	WATTSIMPLE	Curling iron	\N	\N	WATTSIMPLE	90.0	\N	\N	2026-09-09 22:14:32.06663+00	f	\N	unknown	\N	\N	\N	\N
3727bdcf-468a-5d1c-a257-c81a12c06e04	32bc0326-7d0a-5a00-9753-fd6f5f31723e	WATTSIMPLE	String lights (LED, 100 ft)	\N	\N	WATTSIMPLE	15.0	\N	\N	2026-09-09 22:14:32.06663+00	f	\N	unknown	\N	\N	\N	\N
373cb3d2-73b9-5d63-a9f9-20af04bca999	b833c7d7-cc49-5b11-9be3-f541aa8ec840	WATTSIMPLE	Tower fan	\N	\N	WATTSIMPLE	60.0	\N	\N	2026-09-09 22:14:32.06663+00	f	\N	unknown	\N	\N	\N	\N
37ee82b8-36ce-5f60-9602-ded6834548b0	716745a9-712e-5f8c-9d3e-e809fe240b42	WATTSIMPLE	Heated mattress pad	\N	\N	WATTSIMPLE	100.0	\N	\N	2026-09-09 22:14:32.06663+00	f	\N	unknown	\N	\N	\N	\N
3aabdf8b-c306-5586-97df-9db21d662240	716745a9-712e-5f8c-9d3e-e809fe240b42	WATTSIMPLE	Aquarium (55-gallon)	\N	\N	WATTSIMPLE	100.0	\N	\N	2026-09-09 22:14:32.06663+00	f	\N	unknown	\N	\N	\N	\N
3b118fb4-afa9-5df3-b0d5-b1295dd08d70	716745a9-712e-5f8c-9d3e-e809fe240b42	WATTSIMPLE	Washing machine	\N	\N	WATTSIMPLE	500.0	\N	\N	2026-09-09 22:14:32.06663+00	f	\N	unknown	\N	\N	\N	\N
3f1d94a1-9e1d-59ce-b1cb-b593f0cbe658	716745a9-712e-5f8c-9d3e-e809fe240b42	WATTSIMPLE	Waterbed heater	\N	\N	WATTSIMPLE	300.0	\N	\N	2026-09-09 22:14:32.06663+00	f	\N	unknown	\N	\N	\N	\N
3fe1afcc-50a5-5cfe-b12a-b7d6c231a694	716745a9-712e-5f8c-9d3e-e809fe240b42	WATTSIMPLE	Garbage disposal	\N	\N	WATTSIMPLE	550.0	\N	\N	2026-09-09 22:14:32.06663+00	f	\N	unknown	\N	\N	\N	\N
41f1679b-3249-5c3d-adbc-a69e5073b895	0f11d15f-0f7a-5965-9123-a465abfcc20a	WATTSIMPLE	Home server / NAS	\N	\N	WATTSIMPLE	60.0	\N	\N	2026-09-09 22:14:32.06663+00	f	\N	unknown	\N	\N	\N	\N
44a16805-29c2-5f29-85d7-405600ee30be	32bc0326-7d0a-5a00-9753-fd6f5f31723e	WATTSIMPLE	Grow light (600 W)	\N	\N	WATTSIMPLE	600.0	\N	\N	2026-09-09 22:14:32.06663+00	f	\N	unknown	\N	\N	\N	\N
46b0fa27-414b-5660-b882-e7292204d4c4	716745a9-712e-5f8c-9d3e-e809fe240b42	WATTSIMPLE	Pottery kiln (240 V)	\N	\N	WATTSIMPLE	8000.0	\N	\N	2026-09-09 22:14:32.06663+00	f	\N	unknown	\N	\N	\N	\N
4758cbb5-921e-5c0f-99ff-9709efa6ccc4	32bc0326-7d0a-5a00-9753-fd6f5f31723e	WATTSIMPLE	Reptile terrarium (heat + light)	\N	\N	WATTSIMPLE	150.0	\N	\N	2026-09-09 22:14:32.06663+00	f	\N	unknown	\N	\N	\N	\N
47710f05-dbd7-5109-838d-180da0080b78	c0370d52-4de7-5c54-9a84-f38230f1ef98	WATTSIMPLE	Dishwasher	\N	\N	WATTSIMPLE	1800.0	\N	\N	2026-09-09 22:14:32.06663+00	f	\N	unknown	\N	\N	\N	\N
48972fe9-d9a9-5deb-9d18-80a67d6aa724	716745a9-712e-5f8c-9d3e-e809fe240b42	WATTSIMPLE	LED TV (55")	\N	\N	WATTSIMPLE	90.0	\N	\N	2026-09-09 22:14:32.06663+00	f	\N	unknown	\N	\N	\N	\N
49f4043f-3bd7-5715-9f1a-a3953b4ecfa5	716745a9-712e-5f8c-9d3e-e809fe240b42	WATTSIMPLE	Oil-filled radiator	\N	\N	WATTSIMPLE	1500.0	\N	\N	2026-09-09 22:14:32.06663+00	f	\N	unknown	\N	\N	\N	\N
4a9db5e6-6782-5078-9080-5e76ca9d0e55	b474827c-81b2-56d8-8508-786ca0b7c60a	WATTSIMPLE	Coffee maker	\N	\N	WATTSIMPLE	900.0	\N	\N	2026-09-09 22:14:32.06663+00	f	\N	unknown	\N	\N	\N	\N
4d507e9e-de04-5abd-bc87-548136e50309	716745a9-712e-5f8c-9d3e-e809fe240b42	WATTSIMPLE	Wi-Fi router + modem	\N	\N	WATTSIMPLE	20.0	\N	\N	2026-09-09 22:14:32.06663+00	f	\N	unknown	\N	\N	\N	\N
5382eef1-7f08-58fc-94b6-a553f1c48ada	716745a9-712e-5f8c-9d3e-e809fe240b42	WATTSIMPLE	Battery tender (trickle charger)	\N	\N	WATTSIMPLE	30.0	\N	\N	2026-09-09 22:14:32.06663+00	f	\N	unknown	\N	\N	\N	\N
546b47ed-2181-50dc-ab26-02d6b35763d2	716745a9-712e-5f8c-9d3e-e809fe240b42	WATTSIMPLE	Leaf blower (corded)	\N	\N	WATTSIMPLE	1000.0	\N	\N	2026-09-09 22:14:32.06663+00	f	\N	unknown	\N	\N	\N	\N
556f9be1-e614-58df-9046-41034fa2f553	716745a9-712e-5f8c-9d3e-e809fe240b42	WATTSIMPLE	Table saw	\N	\N	WATTSIMPLE	1800.0	\N	\N	2026-09-09 22:14:32.06663+00	f	\N	unknown	\N	\N	\N	\N
606f1a37-6aec-53a3-8569-dc7915983540	716745a9-712e-5f8c-9d3e-e809fe240b42	WATTSIMPLE	Stand mixer	\N	\N	WATTSIMPLE	300.0	\N	\N	2026-09-09 22:14:32.06663+00	f	\N	unknown	\N	\N	\N	\N
626c493e-fe7d-5577-a619-77f8e6d6b1da	716745a9-712e-5f8c-9d3e-e809fe240b42	WATTSIMPLE	Well pump (1 HP)	\N	\N	WATTSIMPLE	1500.0	\N	\N	2026-09-09 22:14:32.06663+00	f	\N	unknown	\N	\N	\N	\N
62de03cf-091d-5b71-844c-283abd1f18e5	716745a9-712e-5f8c-9d3e-e809fe240b42	WATTSIMPLE	Water softener	\N	\N	WATTSIMPLE	70.0	\N	\N	2026-09-09 22:14:32.06663+00	f	\N	unknown	\N	\N	\N	\N
64854c8d-a308-5b33-8f7d-b4c53a85609f	716745a9-712e-5f8c-9d3e-e809fe240b42	WATTSIMPLE	Electric wall heater	\N	\N	WATTSIMPLE	1500.0	\N	\N	2026-09-09 22:14:32.06663+00	f	\N	unknown	\N	\N	\N	\N
64a3fc72-8485-5802-9405-6773a05d8659	716745a9-712e-5f8c-9d3e-e809fe240b42	WATTSIMPLE	Fountain pump	\N	\N	WATTSIMPLE	50.0	\N	\N	2026-09-09 22:14:32.06663+00	f	\N	unknown	\N	\N	\N	\N
656bcc0e-3ec9-5853-8146-9961ce36451d	3c56d755-1b37-5487-a95a-1882b9a6df57	WATTSIMPLE	Range hood	\N	\N	WATTSIMPLE	150.0	\N	\N	2026-09-09 22:14:32.06663+00	f	\N	unknown	\N	\N	\N	\N
67f78757-fb9d-5940-b758-87110fb18545	716745a9-712e-5f8c-9d3e-e809fe240b42	WATTSIMPLE	Egg incubator	\N	\N	WATTSIMPLE	100.0	\N	\N	2026-09-09 22:14:32.06663+00	f	\N	unknown	\N	\N	\N	\N
6e723f60-38c9-5468-89bc-3e4ab4133cb1	716745a9-712e-5f8c-9d3e-e809fe240b42	WATTSIMPLE	Toaster	\N	\N	WATTSIMPLE	1100.0	\N	\N	2026-09-09 22:14:32.06663+00	f	\N	unknown	\N	\N	\N	\N
742f9f97-65a6-5b69-8193-dbed13d1af80	716745a9-712e-5f8c-9d3e-e809fe240b42	WATTSIMPLE	Infrared heater	\N	\N	WATTSIMPLE	1500.0	\N	\N	2026-09-09 22:14:32.06663+00	f	\N	unknown	\N	\N	\N	\N
75d5903f-5504-5817-b3a1-c1e68edf9e7f	716745a9-712e-5f8c-9d3e-e809fe240b42	WATTSIMPLE	Whirlpool tub pump	\N	\N	WATTSIMPLE	1000.0	\N	\N	2026-09-09 22:14:32.06663+00	f	\N	unknown	\N	\N	\N	\N
762936ee-a814-516c-9ca3-d2e21c211167	716745a9-712e-5f8c-9d3e-e809fe240b42	WATTSIMPLE	Espresso machine	\N	\N	WATTSIMPLE	1300.0	\N	\N	2026-09-09 22:14:32.06663+00	f	\N	unknown	\N	\N	\N	\N
7685ed18-b636-55fd-92d4-5765d2697bd3	716745a9-712e-5f8c-9d3e-e809fe240b42	WATTSIMPLE	Slow cooker	\N	\N	WATTSIMPLE	200.0	\N	\N	2026-09-09 22:14:32.06663+00	f	\N	unknown	\N	\N	\N	\N
76a2068e-73ca-5b2d-8709-7e1d06442bf1	716745a9-712e-5f8c-9d3e-e809fe240b42	WATTSIMPLE	Treadmill	\N	\N	WATTSIMPLE	700.0	\N	\N	2026-09-09 22:14:32.06663+00	f	\N	unknown	\N	\N	\N	\N
78e980ec-7aa3-5011-9a88-4ca5c7b0ded6	716745a9-712e-5f8c-9d3e-e809fe240b42	WATTSIMPLE	Central AC (3 ton)	\N	\N	WATTSIMPLE	3500.0	\N	\N	2026-09-09 22:14:32.06663+00	f	\N	unknown	\N	\N	\N	\N
7a45076e-6bcd-57a8-b062-ebc415627f5f	8158deed-5e4c-55db-9f8f-cfbedbe6c2eb	WATTSIMPLE	Heat-pump water heater	\N	\N	WATTSIMPLE	550.0	\N	\N	2026-09-09 22:14:32.06663+00	f	\N	unknown	\N	\N	\N	\N
7ea45957-0715-5412-801a-86c717e01dc0	716745a9-712e-5f8c-9d3e-e809fe240b42	WATTSIMPLE	Garment steamer	\N	\N	WATTSIMPLE	1500.0	\N	\N	2026-09-09 22:14:32.06663+00	f	\N	unknown	\N	\N	\N	\N
7f22d360-7653-5383-85b1-09090af67d12	be389ae9-2387-5726-a7df-feeda9b2e4c4	WATTSIMPLE	Tankless electric water heater (18 kW)	\N	\N	WATTSIMPLE	18000.0	\N	\N	2026-09-09 22:14:32.06663+00	f	\N	unknown	\N	\N	\N	\N
80df0f55-9afa-5ff1-aa36-d0278f1ed187	716745a9-712e-5f8c-9d3e-e809fe240b42	WATTSIMPLE	Mini fridge	\N	\N	WATTSIMPLE	70.0	\N	\N	2026-09-09 22:14:32.06663+00	f	\N	unknown	\N	\N	\N	\N
819f189d-43bd-500c-bfcc-194cf3a5c451	716745a9-712e-5f8c-9d3e-e809fe240b42	WATTSIMPLE	Window AC (10k BTU)	\N	\N	WATTSIMPLE	1200.0	\N	\N	2026-09-09 22:14:32.06663+00	f	\N	unknown	\N	\N	\N	\N
84fb5f93-01a0-5d2e-a020-157dde72584c	32bc0326-7d0a-5a00-9753-fd6f5f31723e	WATTSIMPLE	Fluorescent shop light (2× T8)	\N	\N	WATTSIMPLE	60.0	\N	\N	2026-09-09 22:14:32.06663+00	f	\N	unknown	\N	\N	\N	\N
857baa13-4c17-548f-a750-131af651892f	716745a9-712e-5f8c-9d3e-e809fe240b42	WATTSIMPLE	Robot vacuum (charging)	\N	\N	WATTSIMPLE	40.0	\N	\N	2026-09-09 22:14:32.06663+00	f	\N	unknown	\N	\N	\N	\N
86fdedda-3a03-5d1c-804f-730a1ee9357c	716745a9-712e-5f8c-9d3e-e809fe240b42	WATTSIMPLE	Heated birdbath	\N	\N	WATTSIMPLE	60.0	\N	\N	2026-09-09 22:14:32.06663+00	f	\N	unknown	\N	\N	\N	\N
87d4efd8-f14c-506c-9d49-2047d4a3b4ee	716745a9-712e-5f8c-9d3e-e809fe240b42	WATTSIMPLE	Rice cooker	\N	\N	WATTSIMPLE	500.0	\N	\N	2026-09-09 22:14:32.06663+00	f	\N	unknown	\N	\N	\N	\N
892652b5-b56c-5133-b5c9-7b119ce354f7	44b15223-7bec-5d67-8fac-db985e3e01c5	WATTSIMPLE	Laptop	\N	\N	WATTSIMPLE	60.0	\N	\N	2026-09-09 22:14:32.06663+00	f	\N	unknown	\N	\N	\N	\N
8eceea51-d0f5-5925-a9e5-7f07bc44d1d3	716745a9-712e-5f8c-9d3e-e809fe240b42	WATTSIMPLE	Engine block heater	\N	\N	WATTSIMPLE	800.0	\N	\N	2026-09-09 22:14:32.06663+00	f	\N	unknown	\N	\N	\N	\N
97953522-2bdb-5b35-baa1-4a50a5f269ab	716745a9-712e-5f8c-9d3e-e809fe240b42	WATTSIMPLE	Countertop ice maker	\N	\N	WATTSIMPLE	150.0	\N	\N	2026-09-09 22:14:32.06663+00	f	\N	unknown	\N	\N	\N	\N
97dba6e2-333a-559b-a234-2041cfb37b24	32bc0326-7d0a-5a00-9753-fd6f5f31723e	WATTSIMPLE	Heat lamp (250 W)	\N	\N	WATTSIMPLE	250.0	\N	\N	2026-09-09 22:14:32.06663+00	f	\N	unknown	\N	\N	\N	\N
998e864a-fb67-5928-aed5-74e7c87912c2	b0a058f4-cfe7-5882-a355-0c0298f5ec68	WATTSIMPLE	Air fryer	\N	\N	WATTSIMPLE	1500.0	\N	\N	2026-09-09 22:14:32.06663+00	f	\N	unknown	\N	\N	\N	\N
99c6fa86-2462-527f-90e3-1470e3236916	b9d0e8a2-95d9-5ec9-916b-a71cc0771ea8	WATTSIMPLE	Pool pump	\N	\N	WATTSIMPLE	1100.0	\N	\N	2026-09-09 22:14:32.06663+00	f	\N	unknown	\N	\N	\N	\N
a2e833b9-8cab-5805-bbba-7795d8975943	716745a9-712e-5f8c-9d3e-e809fe240b42	WATTSIMPLE	MIG welder (240 V)	\N	\N	WATTSIMPLE	4000.0	\N	\N	2026-09-09 22:14:32.06663+00	f	\N	unknown	\N	\N	\N	\N
a309a382-0e7b-5ddf-94b3-ddf2a664141b	37d947f0-88cc-55f1-be5b-d59977d45976	WATTSIMPLE	Upright freezer	\N	\N	WATTSIMPLE	150.0	\N	\N	2026-09-09 22:14:32.06663+00	f	\N	unknown	\N	\N	\N	\N
a373394b-f7c7-5f11-b94f-627a5524fd64	716745a9-712e-5f8c-9d3e-e809fe240b42	WATTSIMPLE	Patio heater (electric)	\N	\N	WATTSIMPLE	1500.0	\N	\N	2026-09-09 22:14:32.06663+00	f	\N	unknown	\N	\N	\N	\N
a3d5554f-fa9e-5347-9d39-5e55dedfeb33	716745a9-712e-5f8c-9d3e-e809fe240b42	WATTSIMPLE	LED TV (75")	\N	\N	WATTSIMPLE	150.0	\N	\N	2026-09-09 22:14:32.06663+00	f	\N	unknown	\N	\N	\N	\N
a45aac41-fcad-56f3-bfb6-b648b64ac07b	716745a9-712e-5f8c-9d3e-e809fe240b42	WATTSIMPLE	Soundbar	\N	\N	WATTSIMPLE	30.0	\N	\N	2026-09-09 22:14:32.06663+00	f	\N	unknown	\N	\N	\N	\N
a7cb924a-0674-54c5-acee-27ceba7ba1d7	716745a9-712e-5f8c-9d3e-e809fe240b42	WATTSIMPLE	Flat iron	\N	\N	WATTSIMPLE	150.0	\N	\N	2026-09-09 22:14:32.06663+00	f	\N	unknown	\N	\N	\N	\N
a8bad354-1c0c-5789-adff-6bc66e095e98	716745a9-712e-5f8c-9d3e-e809fe240b42	WATTSIMPLE	Heated pet bed	\N	\N	WATTSIMPLE	40.0	\N	\N	2026-09-09 22:14:32.06663+00	f	\N	unknown	\N	\N	\N	\N
aaf36aef-3004-53d8-9336-c710a5eeab35	32bc0326-7d0a-5a00-9753-fd6f5f31723e	WATTSIMPLE	Incandescent bulb	\N	\N	WATTSIMPLE	60.0	\N	\N	2026-09-09 22:14:32.06663+00	f	\N	unknown	\N	\N	\N	\N
ab9b8262-4def-5648-a518-828b5c3b448b	716745a9-712e-5f8c-9d3e-e809fe240b42	WATTSIMPLE	Golf cart charger	\N	\N	WATTSIMPLE	1000.0	\N	\N	2026-09-09 22:14:32.06663+00	f	\N	unknown	\N	\N	\N	\N
ae33a3d6-86c4-5f6c-8791-98bc7422a73f	716745a9-712e-5f8c-9d3e-e809fe240b42	WATTSIMPLE	Salt chlorinator	\N	\N	WATTSIMPLE	150.0	\N	\N	2026-09-09 22:14:32.06663+00	f	\N	unknown	\N	\N	\N	\N
ae3bc9ec-ee0f-5241-af6e-026405468eea	716745a9-712e-5f8c-9d3e-e809fe240b42	WATTSIMPLE	Mini-split (12k BTU)	\N	\N	WATTSIMPLE	1000.0	\N	\N	2026-09-09 22:14:32.06663+00	f	\N	unknown	\N	\N	\N	\N
ae46e34f-5ac4-51ca-a554-ab6019290414	716745a9-712e-5f8c-9d3e-e809fe240b42	WATTSIMPLE	Chicken coop heater	\N	\N	WATTSIMPLE	250.0	\N	\N	2026-09-09 22:14:32.06663+00	f	\N	unknown	\N	\N	\N	\N
b3396606-e950-53a7-abaf-57e47ced64de	8158deed-5e4c-55db-9f8f-cfbedbe6c2eb	WATTSIMPLE	Pool heat pump	\N	\N	WATTSIMPLE	5000.0	\N	\N	2026-09-09 22:14:32.06663+00	f	\N	unknown	\N	\N	\N	\N
b4ce729b-a9ca-5d7b-adf7-7cdc38be46e7	716745a9-712e-5f8c-9d3e-e809fe240b42	WATTSIMPLE	Blender	\N	\N	WATTSIMPLE	500.0	\N	\N	2026-09-09 22:14:32.06663+00	f	\N	unknown	\N	\N	\N	\N
b5b8fac4-fd37-53c4-8ee3-f21e5f68402f	716745a9-712e-5f8c-9d3e-e809fe240b42	WATTSIMPLE	Towel warmer	\N	\N	WATTSIMPLE	100.0	\N	\N	2026-09-09 22:14:32.06663+00	f	\N	unknown	\N	\N	\N	\N
b651cb70-3840-58ba-9804-3ba2fc85de12	23542654-6769-58e6-9a8e-c8708d8238ff	WATTSIMPLE	Electric griddle	\N	\N	WATTSIMPLE	1200.0	\N	\N	2026-09-09 22:14:32.06663+00	f	\N	unknown	\N	\N	\N	\N
b669fb89-1cfa-55dd-a7cd-2bf74222c4f1	b03224d6-390e-55a5-9ea8-93d8f62bc65c	WATTSIMPLE	Refrigerator	\N	\N	WATTSIMPLE	150.0	\N	\N	2026-09-09 22:14:32.06663+00	f	\N	unknown	\N	\N	\N	\N
b7faf615-2706-5942-b6ad-f9ecf03b64a2	32bc0326-7d0a-5a00-9753-fd6f5f31723e	WATTSIMPLE	Landscape lighting (LED, 10 fixtures)	\N	\N	WATTSIMPLE	50.0	\N	\N	2026-09-09 22:14:32.06663+00	f	\N	unknown	\N	\N	\N	\N
b899a26e-1a9a-5440-9c2b-34b38f9b2c00	8158deed-5e4c-55db-9f8f-cfbedbe6c2eb	WATTSIMPLE	Heat pump	\N	\N	WATTSIMPLE	3000.0	\N	\N	2026-09-09 22:14:32.06663+00	f	\N	unknown	\N	\N	\N	\N
b9d59272-698e-5da1-85f6-0aa2d6f34b3b	716745a9-712e-5f8c-9d3e-e809fe240b42	WATTSIMPLE	Pressure cooker (Instant Pot)	\N	\N	WATTSIMPLE	1000.0	\N	\N	2026-09-09 22:14:32.06663+00	f	\N	unknown	\N	\N	\N	\N
b9dfa989-7145-5ff6-98a2-583ffb0690d8	b04ab192-7d35-522e-a8fe-0b7413e719d9	WATTSIMPLE	Laser printer	\N	\N	WATTSIMPLE	500.0	\N	\N	2026-09-09 22:14:32.06663+00	f	\N	unknown	\N	\N	\N	\N
bb29b129-29d6-5ae2-a9ae-b72970e0d225	b833c7d7-cc49-5b11-9be3-f541aa8ec840	WATTSIMPLE	Attic fan	\N	\N	WATTSIMPLE	300.0	\N	\N	2026-09-09 22:14:32.06663+00	f	\N	unknown	\N	\N	\N	\N
bba2c427-d34c-5d8e-9d2f-bdfcd7b6147d	e30e84bf-b862-5728-8ad3-c6c70a5e50d4	WATTSIMPLE	Dehumidifier	\N	\N	WATTSIMPLE	500.0	\N	\N	2026-09-09 22:14:32.06663+00	f	\N	unknown	\N	\N	\N	\N
bba3d398-cb01-5ff7-9069-1a27138e06e2	37d947f0-88cc-55f1-be5b-d59977d45976	WATTSIMPLE	Chest freezer	\N	\N	WATTSIMPLE	100.0	\N	\N	2026-09-09 22:14:32.06663+00	f	\N	unknown	\N	\N	\N	\N
bc6c4bd4-8b3d-52d3-960d-f380f158656a	716745a9-712e-5f8c-9d3e-e809fe240b42	WATTSIMPLE	Bidet seat (heated)	\N	\N	WATTSIMPLE	50.0	\N	\N	2026-09-09 22:14:32.06663+00	f	\N	unknown	\N	\N	\N	\N
bf96abd1-8e59-51b2-92c0-0bbdcb6488d7	716745a9-712e-5f8c-9d3e-e809fe240b42	WATTSIMPLE	Air compressor (1.5 HP)	\N	\N	WATTSIMPLE	1500.0	\N	\N	2026-09-09 22:14:32.06663+00	f	\N	unknown	\N	\N	\N	\N
c0976841-e945-5be9-a97a-4df1781f1530	3c56d755-1b37-5487-a95a-1882b9a6df57	WATTSIMPLE	Electric range/oven	\N	\N	WATTSIMPLE	3000.0	\N	\N	2026-09-09 22:14:32.06663+00	f	\N	unknown	\N	\N	\N	\N
c119b078-e301-5b2e-950c-5a43538f16d3	716745a9-712e-5f8c-9d3e-e809fe240b42	WATTSIMPLE	E-bike charger	\N	\N	WATTSIMPLE	150.0	\N	\N	2026-09-09 22:14:32.06663+00	f	\N	unknown	\N	\N	\N	\N
c15d9f88-43f3-5c32-b185-2eedced13ff1	716745a9-712e-5f8c-9d3e-e809fe240b42	WATTSIMPLE	Security camera system (4 cams + NVR)	\N	\N	WATTSIMPLE	40.0	\N	\N	2026-09-09 22:14:32.06663+00	f	\N	unknown	\N	\N	\N	\N
c20cd86d-5859-5ee1-9dfc-5c36c4b9e8d7	716745a9-712e-5f8c-9d3e-e809fe240b42	WATTSIMPLE	Home theater projector	\N	\N	WATTSIMPLE	300.0	\N	\N	2026-09-09 22:14:32.06663+00	f	\N	unknown	\N	\N	\N	\N
c2d1b6ce-2afe-5df2-b2fa-848bcd9ac854	716745a9-712e-5f8c-9d3e-e809fe240b42	WATTSIMPLE	Gaming PC	\N	\N	WATTSIMPLE	500.0	\N	\N	2026-09-09 22:14:32.06663+00	f	\N	unknown	\N	\N	\N	\N
c54f1f4e-90fe-538d-904a-5d1b5acb5859	3c56d755-1b37-5487-a95a-1882b9a6df57	WATTSIMPLE	Pellet stove	\N	\N	WATTSIMPLE	300.0	\N	\N	2026-09-09 22:14:32.06663+00	f	\N	unknown	\N	\N	\N	\N
c6c2d84f-c3e3-5793-a567-fd7a95644faf	716745a9-712e-5f8c-9d3e-e809fe240b42	WATTSIMPLE	AV receiver	\N	\N	WATTSIMPLE	250.0	\N	\N	2026-09-09 22:14:32.06663+00	f	\N	unknown	\N	\N	\N	\N
c78a4612-67b0-55aa-8b13-25d70c464c3b	b04ab192-7d35-522e-a8fe-0b7413e719d9	WATTSIMPLE	3D printer	\N	\N	WATTSIMPLE	150.0	\N	\N	2026-09-09 22:14:32.06663+00	f	\N	unknown	\N	\N	\N	\N
c9616d72-8f8d-5e86-ad29-7f4d11de5ae9	716745a9-712e-5f8c-9d3e-e809fe240b42	WATTSIMPLE	Vacuum cleaner (corded)	\N	\N	WATTSIMPLE	1200.0	\N	\N	2026-09-09 22:14:32.06663+00	f	\N	unknown	\N	\N	\N	\N
cb00a3c5-f2d1-5272-9c33-34dca0fe0331	6f44b722-7cc0-51a6-8204-0ed72691b38b	WATTSIMPLE	Electric furnace (10 kW)	\N	\N	WATTSIMPLE	10000.0	\N	\N	2026-09-09 22:14:32.06663+00	f	\N	unknown	\N	\N	\N	\N
cb5f8181-b2b4-589f-96cd-a97d19ce51af	44b15223-7bec-5d67-8fac-db985e3e01c5	WATTSIMPLE	Computer monitor	\N	\N	WATTSIMPLE	30.0	\N	\N	2026-09-09 22:14:32.06663+00	f	\N	unknown	\N	\N	\N	\N
ccba2717-e3d2-5045-815b-7a6cc78ca341	716745a9-712e-5f8c-9d3e-e809fe240b42	WATTSIMPLE	Waffle maker	\N	\N	WATTSIMPLE	1000.0	\N	\N	2026-09-09 22:14:32.06663+00	f	\N	unknown	\N	\N	\N	\N
cd5b2857-7eea-564b-a46d-702f6ecd2e64	716745a9-712e-5f8c-9d3e-e809fe240b42	WATTSIMPLE	Cable/satellite box	\N	\N	WATTSIMPLE	25.0	\N	\N	2026-09-09 22:14:32.06663+00	f	\N	unknown	\N	\N	\N	\N
d5800a45-6e6e-57dd-b5f7-7658c036ca22	716745a9-712e-5f8c-9d3e-e809fe240b42	WATTSIMPLE	Oxygen concentrator	\N	\N	WATTSIMPLE	300.0	\N	\N	2026-09-09 22:14:32.06663+00	f	\N	unknown	\N	\N	\N	\N
d60a3e58-b632-52b5-9f38-6ad93b6ce8bc	716745a9-712e-5f8c-9d3e-e809fe240b42	WATTSIMPLE	Sump pump	\N	\N	WATTSIMPLE	800.0	\N	\N	2026-09-09 22:14:32.06663+00	f	\N	unknown	\N	\N	\N	\N
d799ad8a-e0ec-5064-9fde-8e7d3bd96ef4	716745a9-712e-5f8c-9d3e-e809fe240b42	WATTSIMPLE	Food processor	\N	\N	WATTSIMPLE	500.0	\N	\N	2026-09-09 22:14:32.06663+00	f	\N	unknown	\N	\N	\N	\N
dcfa8697-46b8-5563-9545-61b5a70de382	780845d2-b097-5576-812c-7e4f3a667900	WATTSIMPLE	Air purifier	\N	\N	WATTSIMPLE	50.0	\N	\N	2026-09-09 22:14:32.06663+00	f	\N	unknown	\N	\N	\N	\N
dff49cdd-8a7a-5c9a-825c-475d63420b56	d8ca8c39-31f2-5c42-9f71-6765892d24ac	WATTSIMPLE	Hair dryer	\N	\N	WATTSIMPLE	1500.0	\N	\N	2026-09-09 22:14:32.06663+00	f	\N	unknown	\N	\N	\N	\N
e1ac36a2-7b8f-5a08-b8c8-311fe38ebc2e	716745a9-712e-5f8c-9d3e-e809fe240b42	WATTSIMPLE	Smart speaker	\N	\N	WATTSIMPLE	5.0	\N	\N	2026-09-09 22:14:32.06663+00	f	\N	unknown	\N	\N	\N	\N
e4232be8-fc9f-576d-b45c-877a47c068cf	716745a9-712e-5f8c-9d3e-e809fe240b42	WATTSIMPLE	Sewage ejector pump	\N	\N	WATTSIMPLE	800.0	\N	\N	2026-09-09 22:14:32.06663+00	f	\N	unknown	\N	\N	\N	\N
e95719e1-17bb-5300-bb20-86789cec548f	716745a9-712e-5f8c-9d3e-e809fe240b42	WATTSIMPLE	Streaming stick	\N	\N	WATTSIMPLE	5.0	\N	\N	2026-09-09 22:14:32.06663+00	f	\N	unknown	\N	\N	\N	\N
e95caf80-d10e-54d8-818b-ffab64dd0685	716745a9-712e-5f8c-9d3e-e809fe240b42	WATTSIMPLE	Corded lawn mower	\N	\N	WATTSIMPLE	1200.0	\N	\N	2026-09-09 22:14:32.06663+00	f	\N	unknown	\N	\N	\N	\N
ea258721-54af-5393-90d9-7fe165084596	716745a9-712e-5f8c-9d3e-e809fe240b42	WATTSIMPLE	EV charger (Level 2, 40A)	\N	\N	WATTSIMPLE	9600.0	\N	\N	2026-09-09 22:14:32.06663+00	f	\N	unknown	\N	\N	\N	\N
eab51e47-6f7f-5664-8396-0a3f36100be3	b833c7d7-cc49-5b11-9be3-f541aa8ec840	WATTSIMPLE	Box fan	\N	\N	WATTSIMPLE	75.0	\N	\N	2026-09-09 22:14:32.06663+00	f	\N	unknown	\N	\N	\N	\N
eac79caf-2e02-5206-b020-2b9b8a625830	32bc0326-7d0a-5a00-9753-fd6f5f31723e	WATTSIMPLE	CFL bulb	\N	\N	WATTSIMPLE	14.0	\N	\N	2026-09-09 22:14:32.06663+00	f	\N	unknown	\N	\N	\N	\N
eb030925-709f-51b9-b9bb-99eb1b61d518	716745a9-712e-5f8c-9d3e-e809fe240b42	WATTSIMPLE	Home sauna (6 kW)	\N	\N	WATTSIMPLE	6000.0	\N	\N	2026-09-09 22:14:32.06663+00	f	\N	unknown	\N	\N	\N	\N
ebfee424-8b5a-578a-a28e-87ce76a46683	716745a9-712e-5f8c-9d3e-e809fe240b42	WATTSIMPLE	Electric blanket	\N	\N	WATTSIMPLE	150.0	\N	\N	2026-09-09 22:14:32.06663+00	f	\N	unknown	\N	\N	\N	\N
ed09cfa5-4b68-5108-970d-7d58965da0f2	b833c7d7-cc49-5b11-9be3-f541aa8ec840	WATTSIMPLE	Whole-house fan	\N	\N	WATTSIMPLE	400.0	\N	\N	2026-09-09 22:14:32.06663+00	f	\N	unknown	\N	\N	\N	\N
ed596bfe-9a52-515a-acd1-a058a1804d7e	716745a9-712e-5f8c-9d3e-e809fe240b42	WATTSIMPLE	Electric fireplace	\N	\N	WATTSIMPLE	1400.0	\N	\N	2026-09-09 22:14:32.06663+00	f	\N	unknown	\N	\N	\N	\N
eecdbb05-8c42-51f1-a42d-3cdcd230a079	716745a9-712e-5f8c-9d3e-e809fe240b42	WATTSIMPLE	Septic aerator	\N	\N	WATTSIMPLE	80.0	\N	\N	2026-09-09 22:14:32.06663+00	f	\N	unknown	\N	\N	\N	\N
ef24adc7-f161-530c-b3a7-4b3d222fea5a	716745a9-712e-5f8c-9d3e-e809fe240b42	WATTSIMPLE	Humidifier	\N	\N	WATTSIMPLE	40.0	\N	\N	2026-09-09 22:14:32.06663+00	f	\N	unknown	\N	\N	\N	\N
efd9af9c-6a96-5709-881a-84e682e5ac31	716745a9-712e-5f8c-9d3e-e809fe240b42	WATTSIMPLE	Evaporative (swamp) cooler	\N	\N	WATTSIMPLE	400.0	\N	\N	2026-09-09 22:14:32.06663+00	f	\N	unknown	\N	\N	\N	\N
f213a6ab-9c70-5af3-82e0-b3736c57385b	8158deed-5e4c-55db-9f8f-cfbedbe6c2eb	WATTSIMPLE	Heat-pump dryer	\N	\N	WATTSIMPLE	1000.0	\N	\N	2026-09-09 22:14:32.06663+00	f	\N	unknown	\N	\N	\N	\N
f21aaa19-216a-5246-8666-af19aafd4e36	716745a9-712e-5f8c-9d3e-e809fe240b42	WATTSIMPLE	Electric fence charger	\N	\N	WATTSIMPLE	5.0	\N	\N	2026-09-09 22:14:32.06663+00	f	\N	unknown	\N	\N	\N	\N
f366f744-3214-5ce9-8232-e632aa168399	716745a9-712e-5f8c-9d3e-e809fe240b42	WATTSIMPLE	Game console	\N	\N	WATTSIMPLE	150.0	\N	\N	2026-09-09 22:14:32.06663+00	f	\N	unknown	\N	\N	\N	\N
f3dbac9b-92d8-55c1-b1b1-22aebdcd1c4f	716745a9-712e-5f8c-9d3e-e809fe240b42	WATTSIMPLE	Sewing machine	\N	\N	WATTSIMPLE	100.0	\N	\N	2026-09-09 22:14:32.06663+00	f	\N	unknown	\N	\N	\N	\N
f3df1209-bf50-5923-9f5b-375b6a91101b	d8ca8c39-31f2-5c42-9f71-6765892d24ac	WATTSIMPLE	Clothes dryer (electric)	\N	\N	WATTSIMPLE	3000.0	\N	\N	2026-09-09 22:14:32.06663+00	f	\N	unknown	\N	\N	\N	\N
f50d0e11-63c7-537e-bf2d-67892ba6a8e6	d8ca8c39-31f2-5c42-9f71-6765892d24ac	WATTSIMPLE	Gas dryer (electric motor)	\N	\N	WATTSIMPLE	300.0	\N	\N	2026-09-09 22:14:32.06663+00	f	\N	unknown	\N	\N	\N	\N
f7f33f29-06f2-596c-9001-47d37e73731e	6f44b722-7cc0-51a6-8204-0ed72691b38b	WATTSIMPLE	Furnace blower	\N	\N	WATTSIMPLE	800.0	\N	\N	2026-09-09 22:14:32.06663+00	f	\N	unknown	\N	\N	\N	\N
f8954fdb-7c43-5d23-aa13-8bbf20eeaa62	716745a9-712e-5f8c-9d3e-e809fe240b42	WATTSIMPLE	Portable AC (10k BTU)	\N	\N	WATTSIMPLE	1100.0	\N	\N	2026-09-09 22:14:32.06663+00	f	\N	unknown	\N	\N	\N	\N
fafc87db-6a72-5eec-addc-31e948cdea3f	716745a9-712e-5f8c-9d3e-e809fe240b42	WATTSIMPLE	Snow blower (corded)	\N	\N	WATTSIMPLE	1800.0	\N	\N	2026-09-09 22:14:32.06663+00	f	\N	unknown	\N	\N	\N	\N
feaf41b9-1afd-5f95-9503-2d4cb10f5673	716745a9-712e-5f8c-9d3e-e809fe240b42	WATTSIMPLE	Bug zapper	\N	\N	WATTSIMPLE	40.0	\N	\N	2026-09-09 22:14:32.06663+00	f	\N	unknown	\N	\N	\N	\N
ffdbedca-2725-5c24-b7c4-67ff0891a439	716745a9-712e-5f8c-9d3e-e809fe240b42	WATTSIMPLE	Radiant floor heating (50 sq ft)	\N	\N	WATTSIMPLE	600.0	\N	\N	2026-09-09 22:14:32.06663+00	f	\N	unknown	\N	\N	\N	\N
0041e789-ade6-51bb-b78b-5a85f450b121	b03224d6-390e-55a5-9ea8-93d8f62bc65c	INMETRO	LG|GC-L228FTLK / GC-L228FTL1|003968/2017|127 V	LG	GC-L228FTLK / GC-L228FTL1	inmetro_refrigerators	\N	684.00	\N	2026-10-15 20:58:22.480867+00	f	127 V	monovolt	127	127	57.0	kWh/mes
00a50f6b-0bbf-5ced-9df2-9693510bb283	a869831f-0baa-5dcf-acf7-29b5bb7baeaf	INMETRO	Philco|H200L|002580/2017|220 V	Philco	H200L	inmetro_refrigerators	\N	414.00	\N	2026-10-15 20:58:22.480867+00	f	220 V	monovolt	220	220	34.5	kWh/mes
00ed85f2-7ed0-51c4-81a8-16fdcf010f52	b03224d6-390e-55a5-9ea8-93d8f62bc65c	INMETRO	Samsung|RL4353RBASL/BZ|001495/2017|220 V	Samsung	RL4353RBASL/BZ	inmetro_refrigerators	\N	462.00	\N	2026-10-15 20:58:22.480867+00	f	220 V	monovolt	220	220	38.5	kWh/mes
032758d3-179b-5bd4-9547-eb9e9137df2f	17ec2033-1274-587c-9c08-03f16e660662	INMETRO	Midea|MRC08|001496/2017|127 V	Midea	MRC08	inmetro_refrigerators	\N	165.60	\N	2026-10-15 20:58:22.480867+00	f	127 V	monovolt	127	127	13.8	kWh/mes
03409669-9c5c-5b0c-bba2-1590dd247445	b03224d6-390e-55a5-9ea8-93d8f62bc65c	INMETRO	Britânia|BRF533BD|002671/2020|220 V	Britânia	BRF533BD	inmetro_refrigerators	\N	528.00	\N	2026-10-15 20:58:22.480867+00	f	220 V	monovolt	220	220	44.0	kWh/mes
0485a9f7-9149-5965-a315-194ec8c15052	b03224d6-390e-55a5-9ea8-93d8f62bc65c	INMETRO	BRASTEMP|BRO80|005218/2016|220 V	BRASTEMP	BRO80	inmetro_refrigerators	\N	872.40	\N	2026-10-15 20:58:22.480867+00	f	220 V	monovolt	220	220	72.7	kWh/mes
04dbe577-d889-53a6-b699-036df08f128c	b03224d6-390e-55a5-9ea8-93d8f62bc65c	INMETRO	Panasonic|NR-BT51|5576/2017|127 V	Panasonic	NR-BT51	inmetro_refrigerators	\N	424.80	\N	2026-10-15 20:58:22.480867+00	f	127 V	monovolt	127	127	35.4	kWh/mes
05d694fc-2dc1-50ab-b64a-46122a5d39dd	b03224d6-390e-55a5-9ea8-93d8f62bc65c	INMETRO	Esmaltec|ROC35|002251/2017|127 V	Esmaltec	ROC35	inmetro_refrigerators	\N	270.00	\N	2026-10-15 20:58:22.480867+00	f	127 V	monovolt	127	127	22.5	kWh/mes
069bc08c-4458-5421-95cc-966a0e239e51	b03224d6-390e-55a5-9ea8-93d8f62bc65c	INMETRO	BRASTEMP|BRE59|005218/2016|220 V	BRASTEMP	BRE59	inmetro_refrigerators	\N	804.00	\N	2026-10-15 20:58:22.480867+00	f	220 V	monovolt	220	220	67.0	kWh/mes
06a0e4de-73b1-5baf-9e45-f397a7c2b214	b03224d6-390e-55a5-9ea8-93d8f62bc65c	INMETRO	Esmaltec|ROC31|002251/2017|220 V	Esmaltec	ROC31	inmetro_refrigerators	\N	286.80	\N	2026-10-15 20:58:22.480867+00	f	220 V	monovolt	220	220	23.9	kWh/mes
06f8b1e9-95ba-5a23-b086-2a24fcd662b2	b03224d6-390e-55a5-9ea8-93d8f62bc65c	INMETRO	BERTAZZONI|REF90PIXR|000222/2018|127 V	BERTAZZONI	REF90PIXR	inmetro_refrigerators	\N	469.20	\N	2026-10-15 20:58:22.480867+00	f	127 V	monovolt	127	127	39.1	kWh/mes
06fae684-1766-544c-aaac-6bb0158cd4ad	b03224d6-390e-55a5-9ea8-93d8f62bc65c	INMETRO	Midea|MD-RT468MTA042|002748/2020|220 V	Midea	MD-RT468MTA042	inmetro_refrigerators	\N	417.60	\N	2026-10-15 20:58:22.480867+00	f	220 V	monovolt	220	220	34.8	kWh/mes
072263ce-6e6a-5d55-a9d6-c346c806ac4f	b03224d6-390e-55a5-9ea8-93d8f62bc65c	INMETRO	Electrolux|SH72X_SS72X|005403/2016|127 V	Electrolux	SH72X_SS72X	inmetro_refrigerators	\N	768.00	\N	2026-10-15 20:58:22.480867+00	f	127 V	monovolt	127	127	64.0	kWh/mes
073db8aa-adc0-5d0a-8e86-1ecae058cacf	b03224d6-390e-55a5-9ea8-93d8f62bc65c	INMETRO	Philco|PRF510IP|004318/2020|127 V	Philco	PRF510IP	inmetro_refrigerators	\N	756.00	\N	2026-10-15 20:58:22.480867+00	f	127 V	monovolt	127	127	63.0	kWh/mes
0781cbc6-b110-5432-984e-c39ac0bc4e6a	b03224d6-390e-55a5-9ea8-93d8f62bc65c	INMETRO	LG|GC-X247CSAV / GC-X247CSA1 / GC-X247CQBV / GC-X247CQB1 / GC-X247CSBV / GC-X247CSB1|003968/2017|220 V	LG	GC-X247CSAV / GC-X247CSA1 / GC-X247CQBV / GC-X247CQB1 / GC-X247CSBV / GC-X247CSB1	inmetro_refrigerators	\N	690.00	\N	2026-10-15 20:58:22.480867+00	f	220 V	monovolt	220	220	57.5	kWh/mes
07b2d60c-f2f0-55d3-b1ae-633695ce2a91	17ec2033-1274-587c-9c08-03f16e660662	INMETRO	Galanz|GFb04C01A-Ix220\nGFb04C01A-Pt220\nGFb04C01A-Br220\nGFb04C01A-Ix127\nGFb04C01A-Pt127\nGFb04C01A-Br127|004319/2020|127 V	Galanz	GFb04C01A-Ix220\nGFb04C01A-Pt220\nGFb04C01A-Br220\nGFb04C01A-Ix127\nGFb04C01A-Pt127\nGFb04C01A-Br127	inmetro_refrigerators	\N	182.40	\N	2026-10-15 20:58:22.480867+00	f	127 V	monovolt	127	127	15.2	kWh/mes
08fd7093-1f51-5dc9-93b5-115629167bd5	17ec2033-1274-587c-9c08-03f16e660662	INMETRO	Electrolux|RE80|005401/2016|220 V	Electrolux	RE80	inmetro_refrigerators	\N	208.80	\N	2026-10-15 20:58:22.480867+00	f	220 V	monovolt	220	220	17.4	kWh/mes
08fdb548-e87b-5491-95b2-8f9de9630041	17ec2033-1274-587c-9c08-03f16e660662	INMETRO	Philco|PFG111B|003271/2019|220 V	Philco	PFG111B	inmetro_refrigerators	\N	198.00	\N	2026-10-15 20:58:22.480867+00	f	220 V	monovolt	220	220	16.5	kWh/mes
0986a642-1d64-508a-9856-5ffffb9bbd3d	b03224d6-390e-55a5-9ea8-93d8f62bc65c	INMETRO	BERTAZZONI|REF75PRR|000222/2018|220 V	BERTAZZONI	REF75PRR	inmetro_refrigerators	\N	447.60	\N	2026-10-15 20:58:22.480867+00	f	220 V	monovolt	220	220	37.3	kWh/mes
09cc0c01-b57c-567c-a285-1bc43cedf054	b03224d6-390e-55a5-9ea8-93d8f62bc65c	INMETRO	LG|GM86SDDB / GM86SDDB1|003968/2017|127 V	LG	GM86SDDB / GM86SDDB1	inmetro_refrigerators	\N	740.40	\N	2026-10-15 20:58:22.480867+00	f	127 V	monovolt	127	127	61.7	kWh/mes
0aa9e1c0-c221-5024-a80a-6f579c6519d3	b03224d6-390e-55a5-9ea8-93d8f62bc65c	INMETRO	Samsung|RS65R5411M9/AZ|004878/2019|127 V	Samsung	RS65R5411M9/AZ	inmetro_refrigerators	\N	656.40	\N	2026-10-15 20:58:22.480867+00	f	127 V	monovolt	127	127	54.7	kWh/mes
0b29718a-9223-5056-b78a-b3c399a3bdb1	b03224d6-390e-55a5-9ea8-93d8f62bc65c	INMETRO	Philco|PRF510I|004318/2020|220 V	Philco	PRF510I	inmetro_refrigerators	\N	660.00	\N	2026-10-15 20:58:22.480867+00	f	220 V	monovolt	220	220	55.0	kWh/mes
0c1dd621-45bf-5dd2-b234-20124d083f14	b03224d6-390e-55a5-9ea8-93d8f62bc65c	INMETRO	BRASTEMP|BRC12|005222/2016|220 V	BRASTEMP	BRC12	inmetro_refrigerators	\N	228.00	\N	2026-10-15 20:58:22.480867+00	f	220 V	monovolt	220	220	19.0	kWh/mes
0dbf3a8e-2d18-5234-bee6-8eb90d3939aa	b03224d6-390e-55a5-9ea8-93d8f62bc65c	INMETRO	Philco|PRF504ID|001056/2020|220 V	Philco	PRF504ID	inmetro_refrigerators	\N	612.00	\N	2026-10-15 20:58:22.480867+00	f	220 V	monovolt	220	220	51.0	kWh/mes
0ddba78e-bc52-5e08-b41e-9d4fd2e4af75	a869831f-0baa-5dcf-acf7-29b5bb7baeaf	INMETRO	CONSUL|CHA31|005219/2016|220 V	CONSUL	CHA31	inmetro_refrigerators	\N	554.40	\N	2026-10-15 20:58:22.480867+00	f	220 V	monovolt	220	220	46.2	kWh/mes
0dde50c1-94a7-5f4d-872d-2767fda81e39	b03224d6-390e-55a5-9ea8-93d8f62bc65c	INMETRO	Crissair|RSD 05.2  350 litros 220V|009778/2019|220 V	Crissair	RSD 05.2  350 litros 220V	inmetro_refrigerators	\N	225.60	\N	2026-10-15 20:58:22.480867+00	f	220 V	monovolt	220	220	18.8	kWh/mes
0e68befb-ecca-5b6f-93ff-b51123a8d647	b03224d6-390e-55a5-9ea8-93d8f62bc65c	INMETRO	Philco|PRF504I|001056/2020|127 V	Philco	PRF504I	inmetro_refrigerators	\N	570.00	\N	2026-10-15 20:58:22.480867+00	f	127 V	monovolt	127	127	47.5	kWh/mes
0ea7d369-6fbb-57ff-a1ae-c5df727d5873	a869831f-0baa-5dcf-acf7-29b5bb7baeaf	INMETRO	Midea|RCFA11|003109/2016|127 V	Midea	RCFA11	inmetro_refrigerators	\N	308.40	\N	2026-10-15 20:58:22.480867+00	f	127 V	monovolt	127	127	25.7	kWh/mes
0efbf55f-9865-52a5-8f53-5e1fc475864f	17ec2033-1274-587c-9c08-03f16e660662	INMETRO	Philco|PFG50ICE|003271/2019|220 V	Philco	PFG50ICE	inmetro_refrigerators	\N	144.00	\N	2026-10-15 20:58:22.480867+00	f	220 V	monovolt	220	220	12.0	kWh/mes
0fde0dfc-23af-5663-a90b-fde31266fff9	b03224d6-390e-55a5-9ea8-93d8f62bc65c	INMETRO	CONSUL|CRD49|005217/2016|220 V	CONSUL	CRD49	inmetro_refrigerators	\N	696.00	\N	2026-10-15 20:58:22.480867+00	f	220 V	monovolt	220	220	58.0	kWh/mes
0fe32dde-fffd-58dd-b975-113d270ac70f	b03224d6-390e-55a5-9ea8-93d8f62bc65c	INMETRO	Panasonic|NR-BT40|5576/2017|220 V	Panasonic	NR-BT40	inmetro_refrigerators	\N	540.00	\N	2026-10-15 20:58:22.480867+00	f	220 V	monovolt	220	220	45.0	kWh/mes
108b848a-ede7-53f1-a95e-5a77105730dc	a869831f-0baa-5dcf-acf7-29b5bb7baeaf	INMETRO	Midea|CFA10|003109/2016|220 V	Midea	CFA10	inmetro_refrigerators	\N	277.20	\N	2026-10-15 20:58:22.480867+00	f	220 V	monovolt	220	220	23.1	kWh/mes
108db4e7-e197-5f21-8d34-64b8684aeca5	b03224d6-390e-55a5-9ea8-93d8f62bc65c	INMETRO	Philco|PRF504I|001056/2020|220 V	Philco	PRF504I	inmetro_refrigerators	\N	510.00	\N	2026-10-15 20:58:22.480867+00	f	220 V	monovolt	220	220	42.5	kWh/mes
108f29d8-3dc5-58d7-917c-8352867c2b4b	b03224d6-390e-55a5-9ea8-93d8f62bc65c	INMETRO	Elettromec|REFRI FD 600X2|004429/2016|220 V	Elettromec	REFRI FD 600X2	inmetro_refrigerators	\N	693.60	\N	2026-10-15 20:58:22.480867+00	f	220 V	monovolt	220	220	57.8	kWh/mes
10d92f06-d475-5820-9037-7425a5e14585	b03224d6-390e-55a5-9ea8-93d8f62bc65c	INMETRO	Electrolux|DC49A|005402/2016|127 V	Electrolux	DC49A	inmetro_refrigerators	\N	697.20	\N	2026-10-15 20:58:22.480867+00	f	127 V	monovolt	127	127	58.1	kWh/mes
1103108a-eb32-56a3-a3ff-e7f271dd8933	a869831f-0baa-5dcf-acf7-29b5bb7baeaf	INMETRO	Midea|RCFC41|003109/2016|127 V	Midea	RCFC41	inmetro_refrigerators	\N	464.40	\N	2026-10-15 20:58:22.480867+00	f	127 V	monovolt	127	127	38.7	kWh/mes
111f7966-75f8-5547-9210-42966273132c	a869831f-0baa-5dcf-acf7-29b5bb7baeaf	INMETRO	Midea|RCFA12|003109/2016|220 V	Midea	RCFA12	inmetro_refrigerators	\N	250.80	\N	2026-10-15 20:58:22.480867+00	f	220 V	monovolt	220	220	20.9	kWh/mes
11253ed2-142f-5dc2-be3f-77df92f84751	17ec2033-1274-587c-9c08-03f16e660662	INMETRO	Britânia|BFG94P|007591/2016|220 V	Britânia	BFG94P	inmetro_refrigerators	\N	216.00	\N	2026-10-15 20:58:22.480867+00	f	220 V	monovolt	220	220	18.0	kWh/mes
1140c19a-0e8c-5b0c-9ab6-1fab4dbfe056	b03224d6-390e-55a5-9ea8-93d8f62bc65c	INMETRO	Philco|PRF533I|002671/2020|127 V	Philco	PRF533I	inmetro_refrigerators	\N	504.00	\N	2026-10-15 20:58:22.480867+00	f	127 V	monovolt	127	127	42.0	kWh/mes
114290d6-f4a4-588e-bd9e-cad721855e8f	b03224d6-390e-55a5-9ea8-93d8f62bc65c	INMETRO	Samsung|RF56K9040SR/BZ|007317/2017|220 V	Samsung	RF56K9040SR/BZ	inmetro_refrigerators	\N	960.00	\N	2026-10-15 20:58:22.480867+00	f	220 V	monovolt	220	220	80.0	kWh/mes
114b3fc8-c60e-5236-9cac-fda081d14922	b03224d6-390e-55a5-9ea8-93d8f62bc65c	INMETRO	Philco|PRF406I|008370/2019|220 V	Philco	PRF406I	inmetro_refrigerators	\N	516.00	\N	2026-10-15 20:58:22.480867+00	f	220 V	monovolt	220	220	43.0	kWh/mes
11fd1418-d41c-5aa2-b7ee-ab6a38c80d91	b03224d6-390e-55a5-9ea8-93d8f62bc65c	INMETRO	BRASTEMP|BRM53|005218/2016|127 V	BRASTEMP	BRM53	inmetro_refrigerators	\N	684.00	\N	2026-10-15 20:58:22.480867+00	f	127 V	monovolt	127	127	57.0	kWh/mes
120e2846-3962-5d76-bcdf-979d3242a946	b03224d6-390e-55a5-9ea8-93d8f62bc65c	INMETRO	Britânia|BRF533ID|002671/2020|127 V	Britânia	BRF533ID	inmetro_refrigerators	\N	528.00	\N	2026-10-15 20:58:22.480867+00	f	127 V	monovolt	127	127	44.0	kWh/mes
12d48d73-2096-5792-b786-3e968e40c0a6	b03224d6-390e-55a5-9ea8-93d8f62bc65c	INMETRO	CONSUL|CRE44|005218/2016|220 V	CONSUL	CRE44	inmetro_refrigerators	\N	696.00	\N	2026-10-15 20:58:22.480867+00	f	220 V	monovolt	220	220	58.0	kWh/mes
132eeca1-cb83-54b2-a8e5-f32baef081a0	b03224d6-390e-55a5-9ea8-93d8f62bc65c	INMETRO	CONSUL|CRM35|005218/2016|127 V	CONSUL	CRM35	inmetro_refrigerators	\N	494.40	\N	2026-10-15 20:58:22.480867+00	f	127 V	monovolt	127	127	41.2	kWh/mes
133bc96e-a3dd-5464-9ecb-e00c51827192	b03224d6-390e-55a5-9ea8-93d8f62bc65c	INMETRO	Miele|KF 2801 Vi 220 Volts|003340/2021|220 V	Miele	KF 2801 Vi 220 Volts	inmetro_refrigerators	\N	366.00	\N	2026-10-15 20:58:22.480867+00	f	220 V	monovolt	220	220	30.5	kWh/mes
13d3fd65-5b6e-5ed6-8039-5b1bee498381	b03224d6-390e-55a5-9ea8-93d8f62bc65c	INMETRO	TECNO|TR54FXDA|005755/2019|220 V	TECNO	TR54FXDA	inmetro_refrigerators	\N	498.00	\N	2026-10-15 20:58:22.480867+00	f	220 V	monovolt	220	220	41.5	kWh/mes
143c514c-e4e9-5d73-8de2-78fe438f02c6	b03224d6-390e-55a5-9ea8-93d8f62bc65c	INMETRO	Samsung|RT38K5A0KWW/FZ|001495/2017|220 V	Samsung	RT38K5A0KWW/FZ	inmetro_refrigerators	\N	471.60	\N	2026-10-15 20:58:22.480867+00	f	220 V	monovolt	220	220	39.3	kWh/mes
1533e374-5c3b-54ca-bc48-12fb9fd045db	b03224d6-390e-55a5-9ea8-93d8f62bc65c	INMETRO	Esmaltec|RCD38|002252/2017|127 V	Esmaltec	RCD38	inmetro_refrigerators	\N	492.00	\N	2026-10-15 20:58:22.480867+00	f	127 V	monovolt	127	127	41.0	kWh/mes
15788a28-928d-59b8-aaac-2712c811aff8	a869831f-0baa-5dcf-acf7-29b5bb7baeaf	INMETRO	Philco|PFH160B|003272/2019|220 V	Philco	PFH160B	inmetro_refrigerators	\N	309.60	\N	2026-10-15 20:58:22.480867+00	f	220 V	monovolt	220	220	25.8	kWh/mes
15ed1cdd-f113-55ad-9c36-78e1b41175af	b03224d6-390e-55a5-9ea8-93d8f62bc65c	INMETRO	BERTAZZONI|REF90PIXL|000222/2018|220 V	BERTAZZONI	REF90PIXL	inmetro_refrigerators	\N	469.20	\N	2026-10-15 20:58:22.480867+00	f	220 V	monovolt	220	220	39.1	kWh/mes
15edf523-f758-5426-90cf-9a322f56bae5	b03224d6-390e-55a5-9ea8-93d8f62bc65c	INMETRO	Electrolux|TF55_TF55S|005404/2016|220 V	Electrolux	TF55_TF55S	inmetro_refrigerators	\N	597.60	\N	2026-10-15 20:58:22.480867+00	f	220 V	monovolt	220	220	49.8	kWh/mes
16658e17-50c3-520d-a395-a163cfb779a7	b03224d6-390e-55a5-9ea8-93d8f62bc65c	INMETRO	Samsung|RT46K6A4KWW/FZ|001495/2017|220 V	Samsung	RT46K6A4KWW/FZ	inmetro_refrigerators	\N	499.20	\N	2026-10-15 20:58:22.480867+00	f	220 V	monovolt	220	220	41.6	kWh/mes
16a589c5-2cdf-5b2e-80d7-609be7e3a076	b03224d6-390e-55a5-9ea8-93d8f62bc65c	INMETRO	Samsung|RS58T5561B1/BZ|000243/2019|220 V	Samsung	RS58T5561B1/BZ	inmetro_refrigerators	\N	576.00	\N	2026-10-15 20:58:22.480867+00	f	220 V	monovolt	220	220	48.0	kWh/mes
16b224d3-092a-543e-b71a-8b6fdc8b8d1e	b03224d6-390e-55a5-9ea8-93d8f62bc65c	INMETRO	Continental|TC41_TC41S|005404/2016|127 V	Continental	TC41_TC41S	inmetro_refrigerators	\N	615.60	\N	2026-10-15 20:58:22.480867+00	f	127 V	monovolt	127	127	51.3	kWh/mes
16bc6507-3e8e-5687-9f17-bf349bc75bbf	17ec2033-1274-587c-9c08-03f16e660662	INMETRO	Midea|MRC06B2|001496/2017|220 V	Midea	MRC06B2	inmetro_refrigerators	\N	174.00	\N	2026-10-15 20:58:22.480867+00	f	220 V	monovolt	220	220	14.5	kWh/mes
16cbaa66-0ee1-5946-b126-38c30d14a9c4	a869831f-0baa-5dcf-acf7-29b5bb7baeaf	INMETRO	Electrolux|H550|004053/2020|220 V	Electrolux	H550	inmetro_refrigerators	\N	870.00	\N	2026-10-15 20:58:22.480867+00	f	220 V	monovolt	220	220	72.5	kWh/mes
16cc6814-92cd-55ac-bed7-8cfa0695f379	b03224d6-390e-55a5-9ea8-93d8f62bc65c	INMETRO	Panasonic|NR-BT40|5576/2017|127 V	Panasonic	NR-BT40	inmetro_refrigerators	\N	540.00	\N	2026-10-15 20:58:22.480867+00	f	127 V	monovolt	127	127	45.0	kWh/mes
173b03fa-6325-5b07-89f4-23e727199ea2	b03224d6-390e-55a5-9ea8-93d8f62bc65c	INMETRO	CONSUL|CRM43Z|005218/2016|127 V	CONSUL	CRM43Z	inmetro_refrigerators	\N	624.00	\N	2026-10-15 20:58:22.480867+00	f	127 V	monovolt	127	127	52.0	kWh/mes
175892eb-2bc6-5bea-8779-e008ffd91d59	b03224d6-390e-55a5-9ea8-93d8f62bc65c	INMETRO	Philco|PRF520DIP|008370/2019|220 V	Philco	PRF520DIP	inmetro_refrigerators	\N	735.60	\N	2026-10-15 20:58:22.480867+00	f	220 V	monovolt	220	220	61.3	kWh/mes
18972922-29bf-59de-a33f-a89f6c285b56	17ec2033-1274-587c-9c08-03f16e660662	INMETRO	Philco|PH85PR|007591/2016|220 V	Philco	PH85PR	inmetro_refrigerators	\N	210.00	\N	2026-10-15 20:58:22.480867+00	f	220 V	monovolt	220	220	17.5	kWh/mes
1915326d-69db-5fa3-a162-72ad9983900e	b03224d6-390e-55a5-9ea8-93d8f62bc65c	INMETRO	Samsung|RF49A5202S9/AZ|001495/2017|127 V	Samsung	RF49A5202S9/AZ	inmetro_refrigerators	\N	522.00	\N	2026-10-15 20:58:22.480867+00	f	127 V	monovolt	127	127	43.5	kWh/mes
1934a6b9-76e9-59f0-8ec3-8bdef8ec8cfd	b03224d6-390e-55a5-9ea8-93d8f62bc65c	INMETRO	Philco|PFG100RP|000963/2021|127 V	Philco	PFG100RP	inmetro_refrigerators	\N	266.40	\N	2026-10-15 20:58:22.480867+00	f	127 V	monovolt	127	127	22.2	kWh/mes
196e5127-e741-589b-8817-aeec81a03a43	17ec2033-1274-587c-9c08-03f16e660662	INMETRO	Philco|PFG90I|007591/2016|127 V	Philco	PFG90I	inmetro_refrigerators	\N	216.00	\N	2026-10-15 20:58:22.480867+00	f	127 V	monovolt	127	127	18.0	kWh/mes
19a4e572-b792-5e48-9c0d-255af95ca3db	b03224d6-390e-55a5-9ea8-93d8f62bc65c	INMETRO	Philco|PRF533ID|002671/2020|127 V	Philco	PRF533ID	inmetro_refrigerators	\N	528.00	\N	2026-10-15 20:58:22.480867+00	f	127 V	monovolt	127	127	44.0	kWh/mes
1a87011e-144a-599b-92c3-d8cc7dfda6b5	17ec2033-1274-587c-9c08-03f16e660662	INMETRO	Midea|MRC06B1|001496/2017|127 V	Midea	MRC06B1	inmetro_refrigerators	\N	144.00	\N	2026-10-15 20:58:22.480867+00	f	127 V	monovolt	127	127	12.0	kWh/mes
1a935d66-fb0d-5abf-b293-75c45c4ea4ca	17ec2033-1274-587c-9c08-03f16e660662	INMETRO	Electrolux|RE120|005401/2016|127 V	Electrolux	RE120	inmetro_refrigerators	\N	238.80	\N	2026-10-15 20:58:22.480867+00	f	127 V	monovolt	127	127	19.9	kWh/mes
1aaabdf2-3a96-5266-94de-d355f7ef9bf8	a869831f-0baa-5dcf-acf7-29b5bb7baeaf	INMETRO	CONSUL|CVU26Z|005220/2016|127 V	CONSUL	CVU26Z	inmetro_refrigerators	\N	470.40	\N	2026-10-15 20:58:22.480867+00	f	127 V	monovolt	127	127	39.2	kWh/mes
1c020dc6-4d2e-5d0f-8507-e21d025910eb	b03224d6-390e-55a5-9ea8-93d8f62bc65c	INMETRO	Midea|MD-RS587FGA|002669/2020|220 V	Midea	MD-RS587FGA	inmetro_refrigerators	\N	602.40	\N	2026-10-15 20:58:22.480867+00	f	220 V	monovolt	220	220	50.2	kWh/mes
1ca1d253-ab2f-5c07-bddd-3ab561b0274b	b03224d6-390e-55a5-9ea8-93d8f62bc65c	INMETRO	TECNO|TR65FXDA|005435/2019|127 V	TECNO	TR65FXDA	inmetro_refrigerators	\N	518.40	\N	2026-10-15 20:58:22.480867+00	f	127 V	monovolt	127	127	43.2	kWh/mes
1cc9c1ac-c56a-5a1e-bd26-8b69b6d2febc	b03224d6-390e-55a5-9ea8-93d8f62bc65c	INMETRO	Philco|PRF533IPD|002671/2020|127 V	Philco	PRF533IPD	inmetro_refrigerators	\N	528.00	\N	2026-10-15 20:58:22.480867+00	f	127 V	monovolt	127	127	44.0	kWh/mes
1ce0a166-3874-57c9-8367-c211e6b4fac0	a869831f-0baa-5dcf-acf7-29b5bb7baeaf	INMETRO	Philco|PFH260B|002580/2017|220 V	Philco	PFH260B	inmetro_refrigerators	\N	456.00	\N	2026-10-15 20:58:22.480867+00	f	220 V	monovolt	220	220	38.0	kWh/mes
1d44013b-cfb8-5312-b61b-5f0ec390275a	b03224d6-390e-55a5-9ea8-93d8f62bc65c	INMETRO	LG|GT44BPP / GT44BPP1|003968/2017|220 V	LG	GT44BPP / GT44BPP1	inmetro_refrigerators	\N	415.20	\N	2026-10-15 20:58:22.480867+00	f	220 V	monovolt	220	220	34.6	kWh/mes
1d7864c3-8674-5f3c-9f9a-13a0446e7b63	17ec2033-1274-587c-9c08-03f16e660662	INMETRO	Philco|PFG87B|001955/2017|127 V	Philco	PFG87B	inmetro_refrigerators	\N	163.20	\N	2026-10-15 20:58:22.480867+00	f	127 V	monovolt	127	127	13.6	kWh/mes
1e7a4c60-8b9e-594e-bde7-1a3c3e5405b7	b03224d6-390e-55a5-9ea8-93d8f62bc65c	INMETRO	CONSUL|CRM51|005218/2016|127 V	CONSUL	CRM51	inmetro_refrigerators	\N	630.00	\N	2026-10-15 20:58:22.480867+00	f	127 V	monovolt	127	127	52.5	kWh/mes
1f2889f4-3c34-5ad2-a620-2ad2559eeef4	b03224d6-390e-55a5-9ea8-93d8f62bc65c	INMETRO	Electrolux|DM90X_DM91X|000514/2018|127 V	Electrolux	DM90X_DM91X	inmetro_refrigerators	\N	675.60	\N	2026-10-15 20:58:22.480867+00	f	127 V	monovolt	127	127	56.3	kWh/mes
1fcbfe6f-ca7c-565d-8f22-957752c7fe34	a869831f-0baa-5dcf-acf7-29b5bb7baeaf	INMETRO	EOS|EFH250X|003659/2020|220 V	EOS	EFH250X	inmetro_refrigerators	\N	344.40	\N	2026-10-15 20:58:22.480867+00	f	220 V	monovolt	220	220	28.7	kWh/mes
1fd95f1e-d6db-5734-b344-975ba3986a61	17ec2033-1274-587c-9c08-03f16e660662	INMETRO	EOS|EFB130\nEFB130P|003660/2020|220 V	EOS	EFB130\nEFB130P	inmetro_refrigerators	\N	213.60	\N	2026-10-15 20:58:22.480867+00	f	220 V	monovolt	220	220	17.8	kWh/mes
20ff4466-4bbb-5719-a0fd-f02ca6e6d435	b03224d6-390e-55a5-9ea8-93d8f62bc65c	INMETRO	Philco|PRF505TI|001056/2020|220 V	Philco	PRF505TI	inmetro_refrigerators	\N	480.00	\N	2026-10-15 20:58:22.480867+00	f	220 V	monovolt	220	220	40.0	kWh/mes
2178f0cc-34ce-508b-9fbb-82ca89db4f6e	b03224d6-390e-55a5-9ea8-93d8f62bc65c	INMETRO	BERTAZZONI|REF90PRR|000222/2018|220 V	BERTAZZONI	REF90PRR	inmetro_refrigerators	\N	469.20	\N	2026-10-15 20:58:22.480867+00	f	220 V	monovolt	220	220	39.1	kWh/mes
22525a6c-a453-579a-af5b-079ef1338e95	b03224d6-390e-55a5-9ea8-93d8f62bc65c	INMETRO	CONSUL|CRM39|005218/2016|220 V	CONSUL	CRM39	inmetro_refrigerators	\N	589.20	\N	2026-10-15 20:58:22.480867+00	f	220 V	monovolt	220	220	49.1	kWh/mes
231ffaa4-3f9d-553f-9afb-efa8d7836e5e	17ec2033-1274-587c-9c08-03f16e660662	INMETRO	Philco|PFG50ICE|003271/2019|127 V	Philco	PFG50ICE	inmetro_refrigerators	\N	141.60	\N	2026-10-15 20:58:22.480867+00	f	127 V	monovolt	127	127	11.8	kWh/mes
233dfb49-1595-58aa-9678-dfea1ddd7ccc	b03224d6-390e-55a5-9ea8-93d8f62bc65c	INMETRO	CONSUL|CRM38|005218/2016|220 V	CONSUL	CRM38	inmetro_refrigerators	\N	589.20	\N	2026-10-15 20:58:22.480867+00	f	220 V	monovolt	220	220	49.1	kWh/mes
23f2f0f1-9fca-5ef9-9721-bc404306f92a	b03224d6-390e-55a5-9ea8-93d8f62bc65c	INMETRO	Esmaltec|ROC35|002251/2017|220 V	Esmaltec	ROC35	inmetro_refrigerators	\N	270.00	\N	2026-10-15 20:58:22.480867+00	f	220 V	monovolt	220	220	22.5	kWh/mes
243b5d26-06d7-51b4-b15a-1c51c33a450b	b03224d6-390e-55a5-9ea8-93d8f62bc65c	INMETRO	Electrolux|DM90X_DM91X|000514/2018|220 V	Electrolux	DM90X_DM91X	inmetro_refrigerators	\N	675.60	\N	2026-10-15 20:58:22.480867+00	f	220 V	monovolt	220	220	56.3	kWh/mes
247634b8-9fe6-566f-8bb2-d3b452913150	b03224d6-390e-55a5-9ea8-93d8f62bc65c	INMETRO	Viking Range|VCSB5483 / FDSB5483|007592/2016|127 V	Viking Range	VCSB5483 / FDSB5483	inmetro_refrigerators	\N	1213.20	\N	2026-10-15 20:58:22.480867+00	f	127 V	monovolt	127	127	101.1	kWh/mes
24a4a0f2-d8e7-5558-a33f-ef0d9f5e0552	b03224d6-390e-55a5-9ea8-93d8f62bc65c	INMETRO	Philco|PRF505TI|001056/2020|127 V	Philco	PRF505TI	inmetro_refrigerators	\N	480.00	\N	2026-10-15 20:58:22.480867+00	f	127 V	monovolt	127	127	40.0	kWh/mes
24dc46d7-ec25-5d32-951f-19c8d8834c8e	a869831f-0baa-5dcf-acf7-29b5bb7baeaf	INMETRO	Electrolux|FE18|005399/2016|220 V	Electrolux	FE18	inmetro_refrigerators	\N	501.60	\N	2026-10-15 20:58:22.480867+00	f	220 V	monovolt	220	220	41.8	kWh/mes
25c5c030-25f9-58cd-a201-194c6ff0d4eb	b03224d6-390e-55a5-9ea8-93d8f62bc65c	INMETRO	Miele|K 2801 Vi 127 Volts|001051/2020|127 V	Miele	K 2801 Vi 127 Volts	inmetro_refrigerators	\N	250.80	\N	2026-10-15 20:58:22.480867+00	f	127 V	monovolt	127	127	20.9	kWh/mes
25e424ca-4554-579b-bbe2-6c94e4f1e920	b03224d6-390e-55a5-9ea8-93d8f62bc65c	INMETRO	Panasonic|NR-CB85|3738/2020|127 V	Panasonic	NR-CB85	inmetro_refrigerators	\N	792.00	\N	2026-10-15 20:58:22.480867+00	f	127 V	monovolt	127	127	66.0	kWh/mes
26133641-97df-5f2e-a3d1-81e935c0951e	b03224d6-390e-55a5-9ea8-93d8f62bc65c	INMETRO	CONSUL|CRD37|005217/2016|220 V	CONSUL	CRD37	inmetro_refrigerators	\N	522.00	\N	2026-10-15 20:58:22.480867+00	f	220 V	monovolt	220	220	43.5	kWh/mes
271a33b7-beb5-55dc-9157-fcd9c7516252	b03224d6-390e-55a5-9ea8-93d8f62bc65c	INMETRO	Midea|MD-RT468MTA041|002748/2020|127 V	Midea	MD-RT468MTA041	inmetro_refrigerators	\N	492.00	\N	2026-10-15 20:58:22.480867+00	f	127 V	monovolt	127	127	41.0	kWh/mes
281118db-d58c-51a4-9e85-8a7e669d2475	b03224d6-390e-55a5-9ea8-93d8f62bc65c	INMETRO	BRASTEMP|BRY59|005218/2016|127 V	BRASTEMP	BRY59	inmetro_refrigerators	\N	756.00	\N	2026-10-15 20:58:22.480867+00	f	127 V	monovolt	127	127	63.0	kWh/mes
29a6fc86-29ec-5af4-8342-385921babb18	b03224d6-390e-55a5-9ea8-93d8f62bc65c	INMETRO	Electrolux|DFN39_DFX39_TF39_TF39S|005404/2016|220 V	Electrolux	DFN39_DFX39_TF39_TF39S	inmetro_refrigerators	\N	523.20	\N	2026-10-15 20:58:22.480867+00	f	220 V	monovolt	220	220	43.6	kWh/mes
29adce6d-6c57-5611-a62f-5a9530b299bf	b03224d6-390e-55a5-9ea8-93d8f62bc65c	INMETRO	BRASTEMP|BRM59|005218/2016|220 V	BRASTEMP	BRM59	inmetro_refrigerators	\N	792.00	\N	2026-10-15 20:58:22.480867+00	f	220 V	monovolt	220	220	66.0	kWh/mes
29b15e6e-3973-5967-829d-3d5906e7d01f	b03224d6-390e-55a5-9ea8-93d8f62bc65c	INMETRO	LG|GT51BPP / GT51BPP1|006368/2019|220 V	LG	GT51BPP / GT51BPP1	inmetro_refrigerators	\N	522.00	\N	2026-10-15 20:58:22.480867+00	f	220 V	monovolt	220	220	43.5	kWh/mes
29f0958b-1633-57b0-8cef-6e7fd0b2d519	b03224d6-390e-55a5-9ea8-93d8f62bc65c	INMETRO	CONSUL|CRM42|005218/2016|127 V	CONSUL	CRM42	inmetro_refrigerators	\N	669.60	\N	2026-10-15 20:58:22.480867+00	f	127 V	monovolt	127	127	55.8	kWh/mes
2a5aed07-22a7-56c7-b960-9e97d07ffbc1	b03224d6-390e-55a5-9ea8-93d8f62bc65c	INMETRO	Samsung|RT38K5A0KS9/FZ|001495/2017|127 V	Samsung	RT38K5A0KS9/FZ	inmetro_refrigerators	\N	471.60	\N	2026-10-15 20:58:22.480867+00	f	127 V	monovolt	127	127	39.3	kWh/mes
2a7934e3-c2d9-5ef5-b7a0-be8384973538	b03224d6-390e-55a5-9ea8-93d8f62bc65c	INMETRO	LG|GR-X228NMSM / GR-X228NMS1|005754/2019|220 V	LG	GR-X228NMSM / GR-X228NMS1	inmetro_refrigerators	\N	842.40	\N	2026-10-15 20:58:22.480867+00	f	220 V	monovolt	220	220	70.2	kWh/mes
2a7eeaeb-165f-5ea4-bdbf-d1ffc2c958cf	b03224d6-390e-55a5-9ea8-93d8f62bc65c	INMETRO	Electrolux|DF44_DF44S|005404/2016|127 V	Electrolux	DF44_DF44S	inmetro_refrigerators	\N	675.60	\N	2026-10-15 20:58:22.480867+00	f	127 V	monovolt	127	127	56.3	kWh/mes
2b098c0d-b8a9-5b7f-9949-be7e2d38008d	b03224d6-390e-55a5-9ea8-93d8f62bc65c	INMETRO	Electrolux|DB83_DB83X_DB84_DB84X|005404/2016|220 V	Electrolux	DB83_DB83X_DB84_DB84X	inmetro_refrigerators	\N	816.00	\N	2026-10-15 20:58:22.480867+00	f	220 V	monovolt	220	220	68.0	kWh/mes
2b544f5c-e735-50ab-90bc-305ec700b81e	b03224d6-390e-55a5-9ea8-93d8f62bc65c	INMETRO	Samsung|RL4363RBASL/AZ|001495/2017|127 V	Samsung	RL4363RBASL/AZ	inmetro_refrigerators	\N	462.00	\N	2026-10-15 20:58:22.480867+00	f	127 V	monovolt	127	127	38.5	kWh/mes
2ba80f4c-6cff-5ac8-9331-ea87e773c6c3	b03224d6-390e-55a5-9ea8-93d8f62bc65c	INMETRO	Gorenje|NRKI5182A2|005039/2019|220 V	Gorenje	NRKI5182A2	inmetro_refrigerators	\N	282.00	\N	2026-10-15 20:58:22.480867+00	f	220 V	monovolt	220	220	23.5	kWh/mes
2bcfe159-50d5-59b8-88ce-610161948822	a869831f-0baa-5dcf-acf7-29b5bb7baeaf	INMETRO	Electrolux|H330|004053/2020|220 V	Electrolux	H330	inmetro_refrigerators	\N	555.60	\N	2026-10-15 20:58:22.480867+00	f	220 V	monovolt	220	220	46.3	kWh/mes
2c8b5eed-ac00-57cf-89e8-011606c5cce3	b03224d6-390e-55a5-9ea8-93d8f62bc65c	INMETRO	Philco|PRF533ID|002671/2020|220 V	Philco	PRF533ID	inmetro_refrigerators	\N	528.00	\N	2026-10-15 20:58:22.480867+00	f	220 V	monovolt	220	220	44.0	kWh/mes
2cc2523a-c906-5f8e-8046-c907fe5e8f3d	b03224d6-390e-55a5-9ea8-93d8f62bc65c	INMETRO	Venax|NGV 10|001450/2018|127 V	Venax	NGV 10	inmetro_refrigerators	\N	216.00	\N	2026-10-15 20:58:22.480867+00	f	127 V	monovolt	127	127	18.0	kWh/mes
2d1fdbb7-f0be-57f8-88e3-c32da6136374	b03224d6-390e-55a5-9ea8-93d8f62bc65c	INMETRO	BERTAZZONI|REF36FDFIXNV|005435/2019|127 V	BERTAZZONI	REF36FDFIXNV	inmetro_refrigerators	\N	518.40	\N	2026-10-15 20:58:22.480867+00	f	127 V	monovolt	127	127	43.2	kWh/mes
2dade4fd-9dab-53d6-b155-3147b9d02e54	b03224d6-390e-55a5-9ea8-93d8f62bc65c	INMETRO	CONSUL|CRB39|005223/2016|220 V	CONSUL	CRB39	inmetro_refrigerators	\N	439.20	\N	2026-10-15 20:58:22.480867+00	f	220 V	monovolt	220	220	36.6	kWh/mes
2daf2796-0e84-5011-a8d5-c3d5b4b12786	b03224d6-390e-55a5-9ea8-93d8f62bc65c	INMETRO	Electrolux|DQ90X|000514/2018|127 V	Electrolux	DQ90X	inmetro_refrigerators	\N	750.00	\N	2026-10-15 20:58:22.480867+00	f	127 V	monovolt	127	127	62.5	kWh/mes
2db4bed1-3e65-5764-b749-bdad5382489c	b03224d6-390e-55a5-9ea8-93d8f62bc65c	INMETRO	Philco|PRF380I|002671/2020|127 V	Philco	PRF380I	inmetro_refrigerators	\N	432.00	\N	2026-10-15 20:58:22.480867+00	f	127 V	monovolt	127	127	36.0	kWh/mes
2dcef728-d181-5dea-afd0-a754ce921532	b03224d6-390e-55a5-9ea8-93d8f62bc65c	INMETRO	LG|GR-B413PSJU / GR-B413PSJ1|001421/2019|220 V	LG	GR-B413PSJU / GR-B413PSJ1	inmetro_refrigerators	\N	595.20	\N	2026-10-15 20:58:22.480867+00	f	220 V	monovolt	220	220	49.6	kWh/mes
2e3e24c9-3370-51e6-9d61-b89ec40313c2	b03224d6-390e-55a5-9ea8-93d8f62bc65c	INMETRO	Miele|K 2901 Vi 127 Volts|001051/2020|127 V	Miele	K 2901 Vi 127 Volts	inmetro_refrigerators	\N	277.20	\N	2026-10-15 20:58:22.480867+00	f	127 V	monovolt	127	127	23.1	kWh/mes
2edacd5c-c3d6-5b52-b83c-8747a844e499	b03224d6-390e-55a5-9ea8-93d8f62bc65c	INMETRO	Britânia|BRF533BD|002671/2020|127 V	Britânia	BRF533BD	inmetro_refrigerators	\N	528.00	\N	2026-10-15 20:58:22.480867+00	f	127 V	monovolt	127	127	44.0	kWh/mes
2f116183-9c59-5456-bb94-49e835c81792	b03224d6-390e-55a5-9ea8-93d8f62bc65c	INMETRO	BRASTEMP|BRE58|005218/2016|220 V	BRASTEMP	BRE58	inmetro_refrigerators	\N	828.00	\N	2026-10-15 20:58:22.480867+00	f	220 V	monovolt	220	220	69.0	kWh/mes
307bbf53-984d-51a2-a06e-13f19433f7c5	b03224d6-390e-55a5-9ea8-93d8f62bc65c	INMETRO	Philco|PFG120 Vintage|008093/2017|127 V	Philco	PFG120 Vintage	inmetro_refrigerators	\N	240.00	\N	2026-10-15 20:58:22.480867+00	f	127 V	monovolt	127	127	20.0	kWh/mes
309c0735-9e34-582e-a82d-aefb12b9d5f4	b03224d6-390e-55a5-9ea8-93d8f62bc65c	INMETRO	Midea|MD-RF556FGA|002669/2020|220 V	Midea	MD-RF556FGA	inmetro_refrigerators	\N	554.40	\N	2026-10-15 20:58:22.480867+00	f	220 V	monovolt	220	220	46.2	kWh/mes
30b85a14-b886-5fe3-951f-6539b4212e62	b03224d6-390e-55a5-9ea8-93d8f62bc65c	INMETRO	Viking Range|VCSB5423 / FDSB5423|007592/2016|127 V	Viking Range	VCSB5423 / FDSB5423	inmetro_refrigerators	\N	1222.80	\N	2026-10-15 20:58:22.480867+00	f	127 V	monovolt	127	127	101.9	kWh/mes
31238380-dd10-53f4-9b01-28f121e158e4	b03224d6-390e-55a5-9ea8-93d8f62bc65c	INMETRO	Philco|PFG120 Vintage|008093/2017|220 V	Philco	PFG120 Vintage	inmetro_refrigerators	\N	235.20	\N	2026-10-15 20:58:22.480867+00	f	220 V	monovolt	220	220	19.6	kWh/mes
317f49e8-fa7a-5d8d-be1e-1cec2f17ae4a	b03224d6-390e-55a5-9ea8-93d8f62bc65c	INMETRO	Samsung|RF56K9040SR/AZ|007317/2017|127 V	Samsung	RF56K9040SR/AZ	inmetro_refrigerators	\N	705.60	\N	2026-10-15 20:58:22.480867+00	f	127 V	monovolt	127	127	58.8	kWh/mes
31f9505e-4b53-55db-97fb-00c097b66b83	17ec2033-1274-587c-9c08-03f16e660662	INMETRO	Galanz|GFb07C01A-Ix220\nGFb07C01A-Pt220\nGFb07C01A-Br220\nGFb07C01A-Ix127\nGFb07C01A-Pt127\nGFb07C01A-Br127|004319/2020|220 V	Galanz	GFb07C01A-Ix220\nGFb07C01A-Pt220\nGFb07C01A-Br220\nGFb07C01A-Ix127\nGFb07C01A-Pt127\nGFb07C01A-Br127	inmetro_refrigerators	\N	162.00	\N	2026-10-15 20:58:22.480867+00	f	220 V	monovolt	220	220	13.5	kWh/mes
3270ff78-3a91-59d1-ae51-0d3056ea4d4d	b03224d6-390e-55a5-9ea8-93d8f62bc65c	INMETRO	CONSUL|CRB36|005223/2016|127 V	CONSUL	CRB36	inmetro_refrigerators	\N	426.00	\N	2026-10-15 20:58:22.480867+00	f	127 V	monovolt	127	127	35.5	kWh/mes
3276c8b8-e5c4-53cd-ab90-f59e545c5e4c	17ec2033-1274-587c-9c08-03f16e660662	INMETRO	Philco|PFG85B|003271/2019|127 V	Philco	PFG85B	inmetro_refrigerators	\N	148.80	\N	2026-10-15 20:58:22.480867+00	f	127 V	monovolt	127	127	12.4	kWh/mes
32d929cb-d68c-5eac-b2ef-6b294fb3ab10	a869831f-0baa-5dcf-acf7-29b5bb7baeaf	INMETRO	Viking Range|VCFB5363 / FDFB5363|001954/2017|127 V	Viking Range	VCFB5363 / FDFB5363	inmetro_refrigerators	\N	1080.00	\N	2026-10-15 20:58:22.480867+00	f	127 V	monovolt	127	127	90.0	kWh/mes
333505f4-9bd3-5784-b1f7-e948d0ceca34	b03224d6-390e-55a5-9ea8-93d8f62bc65c	INMETRO	LG|GM86SDDB / GM86SDDB1|003968/2017|220 V	LG	GM86SDDB / GM86SDDB1	inmetro_refrigerators	\N	710.40	\N	2026-10-15 20:58:22.480867+00	f	220 V	monovolt	220	220	59.2	kWh/mes
3338bf6e-4c79-5293-b526-cfb378ed833c	b03224d6-390e-55a5-9ea8-93d8f62bc65c	INMETRO	Samsung|RF22R7351SR/AZ|007317/2017|127 V	Samsung	RF22R7351SR/AZ	inmetro_refrigerators	\N	744.00	\N	2026-10-15 20:58:22.480867+00	f	127 V	monovolt	127	127	62.0	kWh/mes
3360bff5-950d-52a8-99c3-f8216be557c9	b03224d6-390e-55a5-9ea8-93d8f62bc65c	INMETRO	BRASTEMP|BRM56Z|005218/2016|127 V	BRASTEMP	BRM56Z	inmetro_refrigerators	\N	744.00	\N	2026-10-15 20:58:22.480867+00	f	127 V	monovolt	127	127	62.0	kWh/mes
3381e075-686e-50be-9804-8b78074eff94	17ec2033-1274-587c-9c08-03f16e660662	INMETRO	Philco|PFG85ICE|003271/2019|127 V	Philco	PFG85ICE	inmetro_refrigerators	\N	148.80	\N	2026-10-15 20:58:22.480867+00	f	127 V	monovolt	127	127	12.4	kWh/mes
33ad4a30-c5eb-5453-a404-3384a65f8969	17ec2033-1274-587c-9c08-03f16e660662	INMETRO	Philco|PH85 Platinum|007591/2016|127 V	Philco	PH85 Platinum	inmetro_refrigerators	\N	210.00	\N	2026-10-15 20:58:22.480867+00	f	127 V	monovolt	127	127	17.5	kWh/mes
33bd5ae5-d034-5bfa-88a5-8cc58f4ad123	b03224d6-390e-55a5-9ea8-93d8f62bc65c	INMETRO	TECNO|TR54FXDA|005755/2019|127 V	TECNO	TR54FXDA	inmetro_refrigerators	\N	498.00	\N	2026-10-15 20:58:22.480867+00	f	127 V	monovolt	127	127	41.5	kWh/mes
3408b9fc-4c93-54e6-8635-ab2b4c11d732	a869831f-0baa-5dcf-acf7-29b5bb7baeaf	INMETRO	Midea|CFA10|003109/2016|127 V	Midea	CFA10	inmetro_refrigerators	\N	237.60	\N	2026-10-15 20:58:22.480867+00	f	127 V	monovolt	127	127	19.8	kWh/mes
347b1592-6259-5f10-bf0d-304d05949d79	b03224d6-390e-55a5-9ea8-93d8f62bc65c	INMETRO	Samsung|RS50N3413S8/BZ|004878/2019|220 V	Samsung	RS50N3413S8/BZ	inmetro_refrigerators	\N	770.40	\N	2026-10-15 20:58:22.480867+00	f	220 V	monovolt	220	220	64.2	kWh/mes
348caa92-88c9-52e9-866c-ed5fa9b2f3ba	b03224d6-390e-55a5-9ea8-93d8f62bc65c	INMETRO	Midea|MD-RS587FGA|002669/2020|127 V	Midea	MD-RS587FGA	inmetro_refrigerators	\N	660.00	\N	2026-10-15 20:58:22.480867+00	f	127 V	monovolt	127	127	55.0	kWh/mes
34e9b9b4-4699-5c82-93a7-22aa4e5ce10a	b03224d6-390e-55a5-9ea8-93d8f62bc65c	INMETRO	Philco|PRF600I|003507/2020|220 V	Philco	PRF600I	inmetro_refrigerators	\N	588.00	\N	2026-10-15 20:58:22.480867+00	f	220 V	monovolt	220	220	49.0	kWh/mes
35d3f8f6-9b9d-5c77-bab0-20cd0e58c0d4	b03224d6-390e-55a5-9ea8-93d8f62bc65c	INMETRO	CONSUL|CRM55|005218/2016|127 V	CONSUL	CRM55	inmetro_refrigerators	\N	672.00	\N	2026-10-15 20:58:22.480867+00	f	127 V	monovolt	127	127	56.0	kWh/mes
35f47d85-3c05-5fc3-8285-95e83f13dc5f	a869831f-0baa-5dcf-acf7-29b5bb7baeaf	INMETRO	Electrolux|FE26|005399/2016|220 V	Electrolux	FE26	inmetro_refrigerators	\N	524.40	\N	2026-10-15 20:58:22.480867+00	f	220 V	monovolt	220	220	43.7	kWh/mes
362137a1-7dcb-50c3-84e5-73eb154fc438	a869831f-0baa-5dcf-acf7-29b5bb7baeaf	INMETRO	CONSUL|CVU30|005220/2016|220 V	CONSUL	CVU30	inmetro_refrigerators	\N	552.00	\N	2026-10-15 20:58:22.480867+00	f	220 V	monovolt	220	220	46.0	kWh/mes
3784b89e-cc36-5f74-aa21-afe8577ca058	b03224d6-390e-55a5-9ea8-93d8f62bc65c	INMETRO	Electrolux|DFN41_DFX41|005404/2016|127 V	Electrolux	DFN41_DFX41	inmetro_refrigerators	\N	651.60	\N	2026-10-15 20:58:22.480867+00	f	127 V	monovolt	127	127	54.3	kWh/mes
37e513f5-4716-5486-8035-1624f8ec2ebf	b03224d6-390e-55a5-9ea8-93d8f62bc65c	INMETRO	Electrolux|SH72X_SS72X|005403/2016|220 V	Electrolux	SH72X_SS72X	inmetro_refrigerators	\N	768.00	\N	2026-10-15 20:58:22.480867+00	f	220 V	monovolt	220	220	64.0	kWh/mes
381dd822-8e6e-5a45-9195-94324037839a	b03224d6-390e-55a5-9ea8-93d8f62bc65c	INMETRO	Midea|MD-RT453FGA042|002748/2020|220 V	Midea	MD-RT453FGA042	inmetro_refrigerators	\N	504.00	\N	2026-10-15 20:58:22.480867+00	f	220 V	monovolt	220	220	42.0	kWh/mes
38b95cc6-2451-5517-ab48-b85cd62a1a63	a869831f-0baa-5dcf-acf7-29b5bb7baeaf	INMETRO	EOS|EFH350X|003659/2020|220 V	EOS	EFH350X	inmetro_refrigerators	\N	444.00	\N	2026-10-15 20:58:22.480867+00	f	220 V	monovolt	220	220	37.0	kWh/mes
390cb090-09bd-550a-98e6-686e73bdaa02	b03224d6-390e-55a5-9ea8-93d8f62bc65c	INMETRO	Viking Range|VCRB5363 / FDRB5363|007095/2016|127 V	Viking Range	VCRB5363 / FDRB5363	inmetro_refrigerators	\N	373.20	\N	2026-10-15 20:58:22.480867+00	f	127 V	monovolt	127	127	31.1	kWh/mes
397f4958-b9f4-567f-b5fd-eb65c22d963d	17ec2033-1274-587c-9c08-03f16e660662	INMETRO	Galanz|GFb07C01A-Ix220\nGFb07C01A-Pt220\nGFb07C01A-Br220\nGFb07C01A-Ix127\nGFb07C01A-Pt127\nGFb07C01A-Br127|004319/2020|127 V	Galanz	GFb07C01A-Ix220\nGFb07C01A-Pt220\nGFb07C01A-Br220\nGFb07C01A-Ix127\nGFb07C01A-Pt127\nGFb07C01A-Br127	inmetro_refrigerators	\N	168.00	\N	2026-10-15 20:58:22.480867+00	f	127 V	monovolt	127	127	14.0	kWh/mes
399ec804-0fb7-547e-9ef2-ceaa6f98ef2b	b03224d6-390e-55a5-9ea8-93d8f62bc65c	INMETRO	Panasonic|NR-BT51|5576/2017|220 V	Panasonic	NR-BT51	inmetro_refrigerators	\N	424.80	\N	2026-10-15 20:58:22.480867+00	f	220 V	monovolt	220	220	35.4	kWh/mes
39ac44c5-f12e-5851-bed3-ac4095bea125	17ec2033-1274-587c-9c08-03f16e660662	INMETRO	Britânia|BFG50B|007591/2016|220 V	Britânia	BFG50B	inmetro_refrigerators	\N	204.00	\N	2026-10-15 20:58:22.480867+00	f	220 V	monovolt	220	220	17.0	kWh/mes
3a7ec806-734e-5add-94cc-667e7611f0dc	b03224d6-390e-55a5-9ea8-93d8f62bc65c	INMETRO	CONSUL|CRM38|005218/2016|127 V	CONSUL	CRM38	inmetro_refrigerators	\N	589.20	\N	2026-10-15 20:58:22.480867+00	f	127 V	monovolt	127	127	49.1	kWh/mes
3a7f8a31-96e8-5301-8965-278bbb80b221	b03224d6-390e-55a5-9ea8-93d8f62bc65c	INMETRO	Samsung|RT46K6A4KBS/FZ|001495/2017|220 V	Samsung	RT46K6A4KBS/FZ	inmetro_refrigerators	\N	420.00	\N	2026-10-15 20:58:22.480867+00	f	220 V	monovolt	220	220	35.0	kWh/mes
3ab8a02f-a948-5af6-884f-4825c906d180	a869831f-0baa-5dcf-acf7-29b5bb7baeaf	INMETRO	EOS|EFH550XX|003659/2020|127 V	EOS	EFH550XX	inmetro_refrigerators	\N	733.20	\N	2026-10-15 20:58:22.480867+00	f	127 V	monovolt	127	127	61.1	kWh/mes
3bd823ce-0809-5d6f-a896-29b8b08a12f5	a869831f-0baa-5dcf-acf7-29b5bb7baeaf	INMETRO	CONSUL|CVU20|005220/2016|127 V	CONSUL	CVU20	inmetro_refrigerators	\N	458.40	\N	2026-10-15 20:58:22.480867+00	f	127 V	monovolt	127	127	38.2	kWh/mes
3d56b21f-37c0-5b1c-bc4e-fe8bd809e680	a869831f-0baa-5dcf-acf7-29b5bb7baeaf	INMETRO	Electrolux|FE22|005399/2016|127 V	Electrolux	FE22	inmetro_refrigerators	\N	511.20	\N	2026-10-15 20:58:22.480867+00	f	127 V	monovolt	127	127	42.6	kWh/mes
3d95f924-63eb-5296-8427-a9ca6786322c	b03224d6-390e-55a5-9ea8-93d8f62bc65c	INMETRO	BERTAZZONI|REF75PRL|000222/2018|127 V	BERTAZZONI	REF75PRL	inmetro_refrigerators	\N	447.60	\N	2026-10-15 20:58:22.480867+00	f	127 V	monovolt	127	127	37.3	kWh/mes
3f1a4102-1e35-5b4c-a70f-b3f1dd3c2faa	b03224d6-390e-55a5-9ea8-93d8f62bc65c	INMETRO	Electrolux|RE31|005401/2016|127 V	Electrolux	RE31	inmetro_refrigerators	\N	279.60	\N	2026-10-15 20:58:22.480867+00	f	127 V	monovolt	127	127	23.3	kWh/mes
409daf21-5b63-5b95-9c78-60888574d9b7	b03224d6-390e-55a5-9ea8-93d8f62bc65c	INMETRO	Electrolux|IF55_IF55S_IF55B|005404/2016|127 V	Electrolux	IF55_IF55S_IF55B	inmetro_refrigerators	\N	423.60	\N	2026-10-15 20:58:22.480867+00	f	127 V	monovolt	127	127	35.3	kWh/mes
41fb157f-f8e2-57bc-931e-d66bf96a7735	a869831f-0baa-5dcf-acf7-29b5bb7baeaf	INMETRO	Midea|RCFA31|003109/2016|127 V	Midea	RCFA31	inmetro_refrigerators	\N	381.60	\N	2026-10-15 20:58:22.480867+00	f	127 V	monovolt	127	127	31.8	kWh/mes
4305fb6e-a55c-54d9-9841-48a477ca8d4a	b03224d6-390e-55a5-9ea8-93d8f62bc65c	INMETRO	CONSUL|CRB36|005223/2016|220 V	CONSUL	CRB36	inmetro_refrigerators	\N	426.00	\N	2026-10-15 20:58:22.480867+00	f	220 V	monovolt	220	220	35.5	kWh/mes
433bb30d-a35f-5272-805c-63150cb5d2de	a869831f-0baa-5dcf-acf7-29b5bb7baeaf	INMETRO	Philco|PFV300I|005214/2021|127 V	Philco	PFV300I	inmetro_refrigerators	\N	438.00	\N	2026-10-15 20:58:22.480867+00	f	127 V	monovolt	127	127	36.5	kWh/mes
43c1fe91-cae5-5643-bec9-325dd2d9425c	17ec2033-1274-587c-9c08-03f16e660662	INMETRO	Philco|PFG125B|003271/2019|220 V	Philco	PFG125B	inmetro_refrigerators	\N	176.40	\N	2026-10-15 20:58:22.480867+00	f	220 V	monovolt	220	220	14.7	kWh/mes
43d79ab3-30a8-5a42-916b-47e133412105	17ec2033-1274-587c-9c08-03f16e660662	INMETRO	Galanz|GFb12C01A-Ix127\nGFb12C01A-Pt127\nGFb12C01A-Br127\nGFb12C01A-Ix220\nGFb12C01A-Pt220\nGFb12C01A-Br220|004319/2020|220 V	Galanz	GFb12C01A-Ix127\nGFb12C01A-Pt127\nGFb12C01A-Br127\nGFb12C01A-Ix220\nGFb12C01A-Pt220\nGFb12C01A-Br220	inmetro_refrigerators	\N	254.40	\N	2026-10-15 20:58:22.480867+00	f	220 V	monovolt	220	220	21.2	kWh/mes
443c7ef1-a18a-516c-b5d7-4782f13b2068	b03224d6-390e-55a5-9ea8-93d8f62bc65c	INMETRO	Viking Range|RVRF3361|006283/2018|127 V	Viking Range	RVRF3361	inmetro_refrigerators	\N	880.80	\N	2026-10-15 20:58:22.480867+00	f	127 V	monovolt	127	127	73.4	kWh/mes
448f21ac-596d-544f-a202-815b3e2b11f9	b03224d6-390e-55a5-9ea8-93d8f62bc65c	INMETRO	Samsung|RF22R7351SR/BZ|007317/2017|220 V	Samsung	RF22R7351SR/BZ	inmetro_refrigerators	\N	744.00	\N	2026-10-15 20:58:22.480867+00	f	220 V	monovolt	220	220	62.0	kWh/mes
453c9041-dd81-528a-9e73-c024021c4004	a869831f-0baa-5dcf-acf7-29b5bb7baeaf	INMETRO	CONSUL|CHA22|005219/2016|220 V	CONSUL	CHA22	inmetro_refrigerators	\N	432.00	\N	2026-10-15 20:58:22.480867+00	f	220 V	monovolt	220	220	36.0	kWh/mes
46040157-301e-5391-a19d-9d6546267293	17ec2033-1274-587c-9c08-03f16e660662	INMETRO	Philco|PH85N|007591/2016|127 V	Philco	PH85N	inmetro_refrigerators	\N	210.00	\N	2026-10-15 20:58:22.480867+00	f	127 V	monovolt	127	127	17.5	kWh/mes
46b776cb-48b9-5a6c-998b-9961ca2be401	b03224d6-390e-55a5-9ea8-93d8f62bc65c	INMETRO	Electrolux|DC49A|005402/2016|220 V	Electrolux	DC49A	inmetro_refrigerators	\N	697.20	\N	2026-10-15 20:58:22.480867+00	f	220 V	monovolt	220	220	58.1	kWh/mes
46c74229-fc15-5e34-b7b2-d71e18dc2472	b03224d6-390e-55a5-9ea8-93d8f62bc65c	INMETRO	Esmaltec|RCD34|002252/2017|220 V	Esmaltec	RCD34	inmetro_refrigerators	\N	462.00	\N	2026-10-15 20:58:22.480867+00	f	220 V	monovolt	220	220	38.5	kWh/mes
48060b89-b846-5418-a826-1ed8a241d88e	b03224d6-390e-55a5-9ea8-93d8f62bc65c	INMETRO	Samsung|RS58T5561B1/AZ|000243/2019|127 V	Samsung	RS58T5561B1/AZ	inmetro_refrigerators	\N	576.00	\N	2026-10-15 20:58:22.480867+00	f	127 V	monovolt	127	127	48.0	kWh/mes
480dcfd7-3e82-50f2-b615-0cdfd93962f0	b03224d6-390e-55a5-9ea8-93d8f62bc65c	INMETRO	Samsung|RF23R6301SR/AZ|007317/2017|127 V	Samsung	RF23R6301SR/AZ	inmetro_refrigerators	\N	840.00	\N	2026-10-15 20:58:22.480867+00	f	127 V	monovolt	127	127	70.0	kWh/mes
491c367f-7b7f-5e86-b016-ca0514d5518b	17ec2033-1274-587c-9c08-03f16e660662	INMETRO	EOS|EFB130\nEFB130P|003660/2020|127 V	EOS	EFB130\nEFB130P	inmetro_refrigerators	\N	213.60	\N	2026-10-15 20:58:22.480867+00	f	127 V	monovolt	127	127	17.8	kWh/mes
493e0d8e-91c6-5cf2-9254-b4cc60b87e49	b03224d6-390e-55a5-9ea8-93d8f62bc65c	INMETRO	BERTAZZONI|REF90X2|000222/2018|220 V	BERTAZZONI	REF90X2	inmetro_refrigerators	\N	608.40	\N	2026-10-15 20:58:22.480867+00	f	220 V	monovolt	220	220	50.7	kWh/mes
49c7c19c-c6a0-5251-afa6-a8a1dec6142b	b03224d6-390e-55a5-9ea8-93d8f62bc65c	INMETRO	Philco|PFG100RV|000963/2021|127 V	Philco	PFG100RV	inmetro_refrigerators	\N	266.40	\N	2026-10-15 20:58:22.480867+00	f	127 V	monovolt	127	127	22.2	kWh/mes
4a283bcc-bc05-5229-94fd-eeb657560ed5	b03224d6-390e-55a5-9ea8-93d8f62bc65c	INMETRO	Philco|PRF510IP|004318/2020|220 V	Philco	PRF510IP	inmetro_refrigerators	\N	660.00	\N	2026-10-15 20:58:22.480867+00	f	220 V	monovolt	220	220	55.0	kWh/mes
4a28c9ac-928e-50b6-89f0-acd5328659ab	17ec2033-1274-587c-9c08-03f16e660662	INMETRO	Philco|PFG112B|001955/2017|220 V	Philco	PFG112B	inmetro_refrigerators	\N	168.00	\N	2026-10-15 20:58:22.480867+00	f	220 V	monovolt	220	220	14.0	kWh/mes
4a4462b0-d2cb-5ff9-86a0-5be2cc0edf05	a869831f-0baa-5dcf-acf7-29b5bb7baeaf	INMETRO	EOS|EFH150X|003659/2020|127 V	EOS	EFH150X	inmetro_refrigerators	\N	259.20	\N	2026-10-15 20:58:22.480867+00	f	127 V	monovolt	127	127	21.6	kWh/mes
4a4f6d9c-cdd9-5f13-83e5-ea51204b26ed	b03224d6-390e-55a5-9ea8-93d8f62bc65c	INMETRO	Samsung|RT38K5A0KS9/FZ|001495/2017|220 V	Samsung	RT38K5A0KS9/FZ	inmetro_refrigerators	\N	471.60	\N	2026-10-15 20:58:22.480867+00	f	220 V	monovolt	220	220	39.3	kWh/mes
4b63e2d6-1747-5533-b24f-63dc4275c472	b03224d6-390e-55a5-9ea8-93d8f62bc65c	INMETRO	BERTAZZONI|REF90PRL|000222/2018|220 V	BERTAZZONI	REF90PRL	inmetro_refrigerators	\N	469.20	\N	2026-10-15 20:58:22.480867+00	f	220 V	monovolt	220	220	39.1	kWh/mes
4cdfde41-e831-547d-880d-6fad59b2a06b	b03224d6-390e-55a5-9ea8-93d8f62bc65c	INMETRO	Viking Range|VCRB5303 / FDRB5303|007095/2016|127 V	Viking Range	VCRB5303 / FDRB5303	inmetro_refrigerators	\N	399.60	\N	2026-10-15 20:58:22.480867+00	f	127 V	monovolt	127	127	33.3	kWh/mes
4d207006-852f-5e20-9c42-64f32268c8a7	b03224d6-390e-55a5-9ea8-93d8f62bc65c	INMETRO	Midea|MD-RF556FGA|002669/2020|127 V	Midea	MD-RF556FGA	inmetro_refrigerators	\N	588.00	\N	2026-10-15 20:58:22.480867+00	f	127 V	monovolt	127	127	49.0	kWh/mes
4d7f4069-6c77-52e0-928d-ea5a35074bec	17ec2033-1274-587c-9c08-03f16e660662	INMETRO	EOS|EFB50\nEFB50P|003660/2020|127 V	EOS	EFB50\nEFB50P	inmetro_refrigerators	\N	189.60	\N	2026-10-15 20:58:22.480867+00	f	127 V	monovolt	127	127	15.8	kWh/mes
4f00c960-cf62-5d7c-913d-bc1c8ac49d6f	b03224d6-390e-55a5-9ea8-93d8f62bc65c	INMETRO	BRASTEMP|BRO80|005218/2016|127 V	BRASTEMP	BRO80	inmetro_refrigerators	\N	872.40	\N	2026-10-15 20:58:22.480867+00	f	127 V	monovolt	127	127	72.7	kWh/mes
4fac1fec-fe2c-580d-9226-544070101785	b03224d6-390e-55a5-9ea8-93d8f62bc65c	INMETRO	Philco|PRF500I|008370/2019|220 V	Philco	PRF500I	inmetro_refrigerators	\N	560.40	\N	2026-10-15 20:58:22.480867+00	f	220 V	monovolt	220	220	46.7	kWh/mes
4ffc2b01-93e3-5f88-bdf9-110938be5962	b03224d6-390e-55a5-9ea8-93d8f62bc65c	INMETRO	Electrolux|TF55_TF55S|005404/2016|127 V	Electrolux	TF55_TF55S	inmetro_refrigerators	\N	597.60	\N	2026-10-15 20:58:22.480867+00	f	127 V	monovolt	127	127	49.8	kWh/mes
505794c2-4d87-5f78-8db3-3abac41cbfb7	17ec2033-1274-587c-9c08-03f16e660662	INMETRO	Britânia|BFG111B|003271/2019|220 V	Britânia	BFG111B	inmetro_refrigerators	\N	198.00	\N	2026-10-15 20:58:22.480867+00	f	220 V	monovolt	220	220	16.5	kWh/mes
50bccd51-15fe-5261-8ddb-d947867ba2bf	b03224d6-390e-55a5-9ea8-93d8f62bc65c	INMETRO	LG|GC-L247SLUV / GC-L247SLU1|003968/2017|127 V	LG	GC-L247SLUV / GC-L247SLU1	inmetro_refrigerators	\N	690.00	\N	2026-10-15 20:58:22.480867+00	f	127 V	monovolt	127	127	57.5	kWh/mes
51937311-82fc-56a7-bf4f-33defd5d373e	b03224d6-390e-55a5-9ea8-93d8f62bc65c	INMETRO	Panasonic|NR-BT50|5576/2017|220 V	Panasonic	NR-BT50	inmetro_refrigerators	\N	544.80	\N	2026-10-15 20:58:22.480867+00	f	220 V	monovolt	220	220	45.4	kWh/mes
51d2df0c-2047-5566-a1b0-53ca6392a237	b03224d6-390e-55a5-9ea8-93d8f62bc65c	INMETRO	Miele|KF 2901 Vi 127 Volts|001057/2020|127 V	Miele	KF 2901 Vi 127 Volts	inmetro_refrigerators	\N	402.00	\N	2026-10-15 20:58:22.480867+00	f	127 V	monovolt	127	127	33.5	kWh/mes
524a085f-c7d7-50b1-b031-4945850e49bf	17ec2033-1274-587c-9c08-03f16e660662	INMETRO	Philco|PFG85PL|003271/2019|220 V	Philco	PFG85PL	inmetro_refrigerators	\N	145.20	\N	2026-10-15 20:58:22.480867+00	f	220 V	monovolt	220	220	12.1	kWh/mes
52815463-6412-545a-b7d0-51b1c313fc21	b03224d6-390e-55a5-9ea8-93d8f62bc65c	INMETRO	Panasonic|NR-CB85|3738/2020|220 V	Panasonic	NR-CB85	inmetro_refrigerators	\N	792.00	\N	2026-10-15 20:58:22.480867+00	f	220 V	monovolt	220	220	66.0	kWh/mes
539577a9-1429-5979-b0da-93d0be974ed5	b03224d6-390e-55a5-9ea8-93d8f62bc65c	INMETRO	CONSUL|CRC12|005222/2016|220 V	CONSUL	CRC12	inmetro_refrigerators	\N	228.00	\N	2026-10-15 20:58:22.480867+00	f	220 V	monovolt	220	220	19.0	kWh/mes
546efd74-40ae-59a5-be8a-bf6fee1e5b8b	17ec2033-1274-587c-9c08-03f16e660662	INMETRO	Philco|PFG50P|007591/2016|220 V	Philco	PFG50P	inmetro_refrigerators	\N	204.00	\N	2026-10-15 20:58:22.480867+00	f	220 V	monovolt	220	220	17.0	kWh/mes
547215f9-9c29-57f6-91af-8a4ad8cf176e	17ec2033-1274-587c-9c08-03f16e660662	INMETRO	Midea|MRV10|001496/2017|220 V	Midea	MRV10	inmetro_refrigerators	\N	163.20	\N	2026-10-15 20:58:22.480867+00	f	220 V	monovolt	220	220	13.6	kWh/mes
54c3fcd4-189e-50dd-8be5-8ff1c4b8f2a3	b03224d6-390e-55a5-9ea8-93d8f62bc65c	INMETRO	Samsung|RS65R5411M9/BZ|004878/2019|220 V	Samsung	RS65R5411M9/BZ	inmetro_refrigerators	\N	656.40	\N	2026-10-15 20:58:22.480867+00	f	220 V	monovolt	220	220	54.7	kWh/mes
553702b4-2c72-5fb3-a347-d4cd31a739f8	b03224d6-390e-55a5-9ea8-93d8f62bc65c	INMETRO	Samsung|RT53K6240S8/AZ|001495/2017|127 V	Samsung	RT53K6240S8/AZ	inmetro_refrigerators	\N	489.60	\N	2026-10-15 20:58:22.480867+00	f	127 V	monovolt	127	127	40.8	kWh/mes
55ce4716-107a-5c1c-b121-2075db75a5c8	b03224d6-390e-55a5-9ea8-93d8f62bc65c	INMETRO	CONSUL|CRD46|005217/2016|127 V	CONSUL	CRD46	inmetro_refrigerators	\N	645.60	\N	2026-10-15 20:58:22.480867+00	f	127 V	monovolt	127	127	53.8	kWh/mes
55cf6b24-951e-5ec6-9d34-0dad12e9dd39	a869831f-0baa-5dcf-acf7-29b5bb7baeaf	INMETRO	Philco|PFH160B|003272/2019|127 V	Philco	PFH160B	inmetro_refrigerators	\N	334.80	\N	2026-10-15 20:58:22.480867+00	f	127 V	monovolt	127	127	27.9	kWh/mes
574308a0-fe3b-5a87-b99d-a7bc9b9fd7dc	a869831f-0baa-5dcf-acf7-29b5bb7baeaf	INMETRO	Midea|RCFB21|003109/2016|127 V	Midea	RCFB21	inmetro_refrigerators	\N	237.60	\N	2026-10-15 20:58:22.480867+00	f	127 V	monovolt	127	127	19.8	kWh/mes
57a6fc01-9a46-5d80-a922-f48228d9d019	b03224d6-390e-55a5-9ea8-93d8f62bc65c	INMETRO	BERTAZZONI|REF75PIXR|000222/2018|220 V	BERTAZZONI	REF75PIXR	inmetro_refrigerators	\N	447.60	\N	2026-10-15 20:58:22.480867+00	f	220 V	monovolt	220	220	37.3	kWh/mes
57bfe2bd-db6d-5329-bdd2-3bb5aee876ad	b03224d6-390e-55a5-9ea8-93d8f62bc65c	INMETRO	CONSUL|CRD46|005217/2016|220 V	CONSUL	CRD46	inmetro_refrigerators	\N	645.60	\N	2026-10-15 20:58:22.480867+00	f	220 V	monovolt	220	220	53.8	kWh/mes
586a0f4f-122c-503d-807a-e5ebabaf0c30	b03224d6-390e-55a5-9ea8-93d8f62bc65c	INMETRO	BRASTEMP|BRO90|005218/2016|127 V	BRASTEMP	BRO90	inmetro_refrigerators	\N	780.00	\N	2026-10-15 20:58:22.480867+00	f	127 V	monovolt	127	127	65.0	kWh/mes
586e0b04-8f1a-58f1-9827-9251892d7ed5	a869831f-0baa-5dcf-acf7-29b5bb7baeaf	INMETRO	Electrolux|H222|005396/2016|220 V	Electrolux	H222	inmetro_refrigerators	\N	408.00	\N	2026-10-15 20:58:22.480867+00	f	220 V	monovolt	220	220	34.0	kWh/mes
59c02c2e-47c4-5654-b2c3-fb0c1c24eba1	17ec2033-1274-587c-9c08-03f16e660662	INMETRO	Philco|PFG50B|007591/2016|220 V	Philco	PFG50B	inmetro_refrigerators	\N	204.00	\N	2026-10-15 20:58:22.480867+00	f	220 V	monovolt	220	220	17.0	kWh/mes
59caf488-56dd-5756-b6fd-9442b26b294e	a869831f-0baa-5dcf-acf7-29b5bb7baeaf	INMETRO	Philco|PFV205I|004608/2020|127 V	Philco	PFV205I	inmetro_refrigerators	\N	384.00	\N	2026-10-15 20:58:22.480867+00	f	127 V	monovolt	127	127	32.0	kWh/mes
59ea751a-5c7e-57f6-8347-13f9b7b9969b	b03224d6-390e-55a5-9ea8-93d8f62bc65c	INMETRO	BERTAZZONI|REF90X2|000222/2018|127 V	BERTAZZONI	REF90X2	inmetro_refrigerators	\N	608.40	\N	2026-10-15 20:58:22.480867+00	f	127 V	monovolt	127	127	50.7	kWh/mes
5a8c7e0e-fa80-55ed-bcfc-9000b0db031c	b03224d6-390e-55a5-9ea8-93d8f62bc65c	INMETRO	BRASTEMP|BRM54|005218/2016|220 V	BRASTEMP	BRM54	inmetro_refrigerators	\N	684.00	\N	2026-10-15 20:58:22.480867+00	f	220 V	monovolt	220	220	57.0	kWh/mes
5a9e74b0-d68c-55c8-a474-c97b86c2f5dd	b03224d6-390e-55a5-9ea8-93d8f62bc65c	INMETRO	BRASTEMP|BRO90|005218/2016|220 V	BRASTEMP	BRO90	inmetro_refrigerators	\N	780.00	\N	2026-10-15 20:58:22.480867+00	f	220 V	monovolt	220	220	65.0	kWh/mes
5ac5f191-c489-5a9f-8470-f59f83cad235	b03224d6-390e-55a5-9ea8-93d8f62bc65c	INMETRO	Electrolux|RFE39|005397/2016|127 V	Electrolux	RFE39	inmetro_refrigerators	\N	450.00	\N	2026-10-15 20:58:22.480867+00	f	127 V	monovolt	127	127	37.5	kWh/mes
5b923af0-c384-56eb-aab9-19ee8c51bc17	b03224d6-390e-55a5-9ea8-93d8f62bc65c	INMETRO	Samsung|RF27T5501SG/AZ|000243/2019|127 V	Samsung	RF27T5501SG/AZ	inmetro_refrigerators	\N	720.00	\N	2026-10-15 20:58:22.480867+00	f	127 V	monovolt	127	127	60.0	kWh/mes
5beb2eb5-0759-5794-980c-edd08aa33e5d	b03224d6-390e-55a5-9ea8-93d8f62bc65c	INMETRO	CONSUL|CRM50|005218/2016|220 V	CONSUL	CRM50	inmetro_refrigerators	\N	672.00	\N	2026-10-15 20:58:22.480867+00	f	220 V	monovolt	220	220	56.0	kWh/mes
5d48174d-3e85-5cd2-afd7-a6dcc45bc883	b03224d6-390e-55a5-9ea8-93d8f62bc65c	INMETRO	Panasonic|NR-BB53|5576/2017|220 V	Panasonic	NR-BB53	inmetro_refrigerators	\N	478.80	\N	2026-10-15 20:58:22.480867+00	f	220 V	monovolt	220	220	39.9	kWh/mes
5db5a7ea-d644-5a78-a5d1-401c531261b9	17ec2033-1274-587c-9c08-03f16e660662	INMETRO	Electrolux|RE80|005401/2016|127 V	Electrolux	RE80	inmetro_refrigerators	\N	208.80	\N	2026-10-15 20:58:22.480867+00	f	127 V	monovolt	127	127	17.4	kWh/mes
5e02848c-b92a-57f6-909f-bf5936108cbc	b03224d6-390e-55a5-9ea8-93d8f62bc65c	INMETRO	Esmaltec|ROC35R|002251/2017|220 V	Esmaltec	ROC35R	inmetro_refrigerators	\N	262.80	\N	2026-10-15 20:58:22.480867+00	f	220 V	monovolt	220	220	21.9	kWh/mes
5e0a29c7-681f-5f1e-8324-9dd6654c4ea3	b03224d6-390e-55a5-9ea8-93d8f62bc65c	INMETRO	TECNO|TR14GXDA|004358/2020|127 V	TECNO	TR14GXDA	inmetro_refrigerators	\N	284.40	\N	2026-10-15 20:58:22.480867+00	f	127 V	monovolt	127	127	23.7	kWh/mes
5e3960f6-4f97-5456-81bf-8cab86c6b7ce	b03224d6-390e-55a5-9ea8-93d8f62bc65c	INMETRO	BRASTEMP|BRM56|005218/2016|127 V	BRASTEMP	BRM56	inmetro_refrigerators	\N	780.00	\N	2026-10-15 20:58:22.480867+00	f	127 V	monovolt	127	127	65.0	kWh/mes
5e4acae3-a3ab-54e7-b194-6caa26fe758e	b03224d6-390e-55a5-9ea8-93d8f62bc65c	INMETRO	BERTAZZONI|REF36FDFIXNV|005435/2019|220 V	BERTAZZONI	REF36FDFIXNV	inmetro_refrigerators	\N	518.40	\N	2026-10-15 20:58:22.480867+00	f	220 V	monovolt	220	220	43.2	kWh/mes
5ef73682-0df3-5359-8af5-f0dd2ec0b51f	17ec2033-1274-587c-9c08-03f16e660662	INMETRO	Philco|PFG51B|001955/2017|220 V	Philco	PFG51B	inmetro_refrigerators	\N	192.00	\N	2026-10-15 20:58:22.480867+00	f	220 V	monovolt	220	220	16.0	kWh/mes
6019e921-c079-55aa-ad01-aa9e54e445a8	b03224d6-390e-55a5-9ea8-93d8f62bc65c	INMETRO	LG|GC-B659BSB / GC-B659BSB1|003968/2017|127 V	LG	GC-B659BSB / GC-B659BSB1	inmetro_refrigerators	\N	399.60	\N	2026-10-15 20:58:22.480867+00	f	127 V	monovolt	127	127	33.3	kWh/mes
602851f1-2743-5584-a66b-9f62407bada0	17ec2033-1274-587c-9c08-03f16e660662	INMETRO	Philco|PFG125B|003271/2019|127 V	Philco	PFG125B	inmetro_refrigerators	\N	182.40	\N	2026-10-15 20:58:22.480867+00	f	127 V	monovolt	127	127	15.2	kWh/mes
605740fc-6254-5aeb-b9e4-07ec324a16b5	b03224d6-390e-55a5-9ea8-93d8f62bc65c	INMETRO	Philco|PRF260RP|003507/2020|127 V	Philco	PRF260RP	inmetro_refrigerators	\N	420.00	\N	2026-10-15 20:58:22.480867+00	f	127 V	monovolt	127	127	35.0	kWh/mes
611f09bc-3b83-57ec-af70-d7cf07f7d1f8	17ec2033-1274-587c-9c08-03f16e660662	INMETRO	Britânia|BFG85PL|003271/2019|220 V	Britânia	BFG85PL	inmetro_refrigerators	\N	145.20	\N	2026-10-15 20:58:22.480867+00	f	220 V	monovolt	220	220	12.1	kWh/mes
62bb4ca2-1ea2-5677-b42f-c1033864986b	b03224d6-390e-55a5-9ea8-93d8f62bc65c	INMETRO	Panasonic|NR-BT50|5576/2017|127 V	Panasonic	NR-BT50	inmetro_refrigerators	\N	544.80	\N	2026-10-15 20:58:22.480867+00	f	127 V	monovolt	127	127	45.4	kWh/mes
62d38c29-3efe-54b2-adef-91c06f61057d	b03224d6-390e-55a5-9ea8-93d8f62bc65c	INMETRO	Electrolux|IB52_IB52X_IB53_IB53X|005404/2016|127 V	Electrolux	IB52_IB52X_IB53_IB53X	inmetro_refrigerators	\N	548.40	\N	2026-10-15 20:58:22.480867+00	f	127 V	monovolt	127	127	45.7	kWh/mes
638b794e-fa29-5d58-b2d8-9dd16f433575	b03224d6-390e-55a5-9ea8-93d8f62bc65c	INMETRO	Samsung|RT53K6240S8/BZ|001495/2017|220 V	Samsung	RT53K6240S8/BZ	inmetro_refrigerators	\N	489.60	\N	2026-10-15 20:58:22.480867+00	f	220 V	monovolt	220	220	40.8	kWh/mes
643feb62-0e43-544d-a4ba-d0290ebf3c9d	b03224d6-390e-55a5-9ea8-93d8f62bc65c	INMETRO	TECNO|TR45FXDA|005755/2019|127 V	TECNO	TR45FXDA	inmetro_refrigerators	\N	601.20	\N	2026-10-15 20:58:22.480867+00	f	127 V	monovolt	127	127	50.1	kWh/mes
647ed1bb-70d7-5826-96cd-982335d27b58	a869831f-0baa-5dcf-acf7-29b5bb7baeaf	INMETRO	BRASTEMP|BVR28|005221/2016|220 V	BRASTEMP	BVR28	inmetro_refrigerators	\N	660.00	\N	2026-10-15 20:58:22.480867+00	f	220 V	monovolt	220	220	55.0	kWh/mes
65dd613d-0686-559e-82bc-d7898597f331	b03224d6-390e-55a5-9ea8-93d8f62bc65c	INMETRO	Philco|PRF520DIP|008370/2019|127 V	Philco	PRF520DIP	inmetro_refrigerators	\N	715.20	\N	2026-10-15 20:58:22.480867+00	f	127 V	monovolt	127	127	59.6	kWh/mes
6615b40a-7f3c-56cc-a880-8c0ed4bae11e	a869831f-0baa-5dcf-acf7-29b5bb7baeaf	INMETRO	CONSUL|CHA22|005219/2016|127 V	CONSUL	CHA22	inmetro_refrigerators	\N	432.00	\N	2026-10-15 20:58:22.480867+00	f	127 V	monovolt	127	127	36.0	kWh/mes
6664686a-ebef-53a4-a507-e397d09fc6a8	b03224d6-390e-55a5-9ea8-93d8f62bc65c	INMETRO	CONSUL|CRB39|005223/2016|127 V	CONSUL	CRB39	inmetro_refrigerators	\N	439.20	\N	2026-10-15 20:58:22.480867+00	f	127 V	monovolt	127	127	36.6	kWh/mes
66ae7a37-c26d-544a-8ac7-ad79132d0738	b03224d6-390e-55a5-9ea8-93d8f62bc65c	INMETRO	Panasonic|NR-BT42|5576/2017|127 V	Panasonic	NR-BT42	inmetro_refrigerators	\N	372.00	\N	2026-10-15 20:58:22.480867+00	f	127 V	monovolt	127	127	31.0	kWh/mes
66c2a79a-48f2-599c-8834-a9f2baa88865	b03224d6-390e-55a5-9ea8-93d8f62bc65c	INMETRO	Esmaltec|ROC31R|002251/2017|127 V	Esmaltec	ROC31R	inmetro_refrigerators	\N	282.00	\N	2026-10-15 20:58:22.480867+00	f	127 V	monovolt	127	127	23.5	kWh/mes
66e1f22f-7e39-5347-8b99-c8152f558f61	b03224d6-390e-55a5-9ea8-93d8f62bc65c	INMETRO	BRASTEMP|BRM53|005218/2016|220 V	BRASTEMP	BRM53	inmetro_refrigerators	\N	684.00	\N	2026-10-15 20:58:22.480867+00	f	220 V	monovolt	220	220	57.0	kWh/mes
67ca53c4-1c7f-56bc-bb66-36480a7e70db	b03224d6-390e-55a5-9ea8-93d8f62bc65c	INMETRO	BRASTEMP|BRM57|005218/2016|220 V	BRASTEMP	BRM57	inmetro_refrigerators	\N	828.00	\N	2026-10-15 20:58:22.480867+00	f	220 V	monovolt	220	220	69.0	kWh/mes
67e5737f-f532-5456-a6a8-ee9508ed2f74	17ec2033-1274-587c-9c08-03f16e660662	INMETRO	Midea|MRC12B2|001496/2017|220 V	Midea	MRC12B2	inmetro_refrigerators	\N	171.60	\N	2026-10-15 20:58:22.480867+00	f	220 V	monovolt	220	220	14.3	kWh/mes
6813d159-46b7-5e0a-a6b1-be833339955d	b03224d6-390e-55a5-9ea8-93d8f62bc65c	INMETRO	Philco|PRF533IPD|002671/2020|220 V	Philco	PRF533IPD	inmetro_refrigerators	\N	528.00	\N	2026-10-15 20:58:22.480867+00	f	220 V	monovolt	220	220	44.0	kWh/mes
682a6805-5828-5853-a837-453e6659def7	a869831f-0baa-5dcf-acf7-29b5bb7baeaf	INMETRO	Midea|RCFB22|003109/2016|220 V	Midea	RCFB22	inmetro_refrigerators	\N	277.20	\N	2026-10-15 20:58:22.480867+00	f	220 V	monovolt	220	220	23.1	kWh/mes
68516666-855a-5cfb-8b17-6416ab550e26	b03224d6-390e-55a5-9ea8-93d8f62bc65c	INMETRO	CONSUL|CRM52|005218/2016|127 V	CONSUL	CRM52	inmetro_refrigerators	\N	630.00	\N	2026-10-15 20:58:22.480867+00	f	127 V	monovolt	127	127	52.5	kWh/mes
690ddcdc-b0b8-5831-b9a1-3a36ad9e50aa	b03224d6-390e-55a5-9ea8-93d8f62bc65c	INMETRO	BRASTEMP|GRO80|005218/2016|220 V	BRASTEMP	GRO80	inmetro_refrigerators	\N	872.40	\N	2026-10-15 20:58:22.480867+00	f	220 V	monovolt	220	220	72.7	kWh/mes
69349d9b-ea05-5bcf-8319-3ddab87bf3c5	b03224d6-390e-55a5-9ea8-93d8f62bc65c	INMETRO	BERTAZZONI|REF90PRR|000222/2018|127 V	BERTAZZONI	REF90PRR	inmetro_refrigerators	\N	469.20	\N	2026-10-15 20:58:22.480867+00	f	127 V	monovolt	127	127	39.1	kWh/mes
694e4104-4f35-5c77-a70e-6de6f3c5f46c	b03224d6-390e-55a5-9ea8-93d8f62bc65c	INMETRO	CONSUL|CRA30|005222/2016|220 V	CONSUL	CRA30	inmetro_refrigerators	\N	291.60	\N	2026-10-15 20:58:22.480867+00	f	220 V	monovolt	220	220	24.3	kWh/mes
6a1521f9-2e73-512a-b0be-d5519945fa6d	a869831f-0baa-5dcf-acf7-29b5bb7baeaf	INMETRO	Electrolux|FE26|005399/2016|127 V	Electrolux	FE26	inmetro_refrigerators	\N	524.40	\N	2026-10-15 20:58:22.480867+00	f	127 V	monovolt	127	127	43.7	kWh/mes
6b729230-38e2-5c03-b49d-58617b5508e0	17ec2033-1274-587c-9c08-03f16e660662	INMETRO	Philco|PFG107RV|001955/2017|127 V	Philco	PFG107RV	inmetro_refrigerators	\N	210.00	\N	2026-10-15 20:58:22.480867+00	f	127 V	monovolt	127	127	17.5	kWh/mes
6b78b9d9-cf4b-590e-8b0d-685849c91ddf	a869831f-0baa-5dcf-acf7-29b5bb7baeaf	INMETRO	Britânia|BFH162B|003272/2019|127 V	Britânia	BFH162B	inmetro_refrigerators	\N	334.80	\N	2026-10-15 20:58:22.480867+00	f	127 V	monovolt	127	127	27.9	kWh/mes
6c41857b-23c2-5c58-9488-d587d42eb2c7	b03224d6-390e-55a5-9ea8-93d8f62bc65c	INMETRO	Electrolux|DF80_DF80X_DF82_DF82X|005404/2016|220 V	Electrolux	DF80_DF80X_DF82_DF82X	inmetro_refrigerators	\N	852.00	\N	2026-10-15 20:58:22.480867+00	f	220 V	monovolt	220	220	71.0	kWh/mes
6c79223f-aee6-5d11-abcf-b48f8883ce59	b03224d6-390e-55a5-9ea8-93d8f62bc65c	INMETRO	Electrolux|DF44_DF44S|005404/2016|220 V	Electrolux	DF44_DF44S	inmetro_refrigerators	\N	675.60	\N	2026-10-15 20:58:22.480867+00	f	220 V	monovolt	220	220	56.3	kWh/mes
6ccae49f-ecb7-5c39-b6a9-ea51afc2744c	b03224d6-390e-55a5-9ea8-93d8f62bc65c	INMETRO	Philco|PRF500I|008370/2019|127 V	Philco	PRF500I	inmetro_refrigerators	\N	534.00	\N	2026-10-15 20:58:22.480867+00	f	127 V	monovolt	127	127	44.5	kWh/mes
6ce04a22-c1ed-5fa4-9ef3-4bbedf1cc7c6	17ec2033-1274-587c-9c08-03f16e660662	INMETRO	Electrolux|BEER2|006524/2018|127 V	Electrolux	BEER2	inmetro_refrigerators	\N	204.00	\N	2026-10-15 20:58:22.480867+00	f	127 V	monovolt	127	127	17.0	kWh/mes
6ced8736-9846-50cf-b40f-da81d6433ed4	b03224d6-390e-55a5-9ea8-93d8f62bc65c	INMETRO	Electrolux|DM85X_DM86X_DM86V|005404/2016|220 V	Electrolux	DM85X_DM86X_DM86V	inmetro_refrigerators	\N	828.00	\N	2026-10-15 20:58:22.480867+00	f	220 V	monovolt	220	220	69.0	kWh/mes
6d8d4159-8528-5920-8bfd-1654b1bcb4fd	b03224d6-390e-55a5-9ea8-93d8f62bc65c	INMETRO	Toshiba|GR-RF646WEPMA|002669/2020|220 V	Toshiba	GR-RF646WEPMA	inmetro_refrigerators	\N	698.40	\N	2026-10-15 20:58:22.480867+00	f	220 V	monovolt	220	220	58.2	kWh/mes
6dad539d-bb93-564e-a0f7-49929a803d63	b03224d6-390e-55a5-9ea8-93d8f62bc65c	INMETRO	CONSUL|CRM56|005218/2016|220 V	CONSUL	CRM56	inmetro_refrigerators	\N	708.00	\N	2026-10-15 20:58:22.480867+00	f	220 V	monovolt	220	220	59.0	kWh/mes
6e0086f9-240a-532b-936c-fcfff6b6adb7	b03224d6-390e-55a5-9ea8-93d8f62bc65c	INMETRO	BRASTEMP|BRM58|005218/2016|220 V	BRASTEMP	BRM58	inmetro_refrigerators	\N	828.00	\N	2026-10-15 20:58:22.480867+00	f	220 V	monovolt	220	220	69.0	kWh/mes
6e90749e-fafc-5c9a-aba8-6ecbeccc3f1f	b03224d6-390e-55a5-9ea8-93d8f62bc65c	INMETRO	BRASTEMP|BRE58|005218/2016|127 V	BRASTEMP	BRE58	inmetro_refrigerators	\N	828.00	\N	2026-10-15 20:58:22.480867+00	f	127 V	monovolt	127	127	69.0	kWh/mes
6f1fa6ac-458c-5d87-afd1-0ba5a9bd53ae	b03224d6-390e-55a5-9ea8-93d8f62bc65c	INMETRO	Miele|KF 2901 Vi 220 Volts|003340/2021|220 V	Miele	KF 2901 Vi 220 Volts	inmetro_refrigerators	\N	355.20	\N	2026-10-15 20:58:22.480867+00	f	220 V	monovolt	220	220	29.6	kWh/mes
6f91cce3-b3ff-5a13-b88e-b8f565fb9294	b03224d6-390e-55a5-9ea8-93d8f62bc65c	INMETRO	BRASTEMP|BRS62|005218/2016|127 V	BRASTEMP	BRS62	inmetro_refrigerators	\N	804.00	\N	2026-10-15 20:58:22.480867+00	f	127 V	monovolt	127	127	67.0	kWh/mes
6fe5d886-d0c4-5baa-9578-917402da08bc	b03224d6-390e-55a5-9ea8-93d8f62bc65c	INMETRO	CONSUL|CRM35|005218/2016|220 V	CONSUL	CRM35	inmetro_refrigerators	\N	494.40	\N	2026-10-15 20:58:22.480867+00	f	220 V	monovolt	220	220	41.2	kWh/mes
701491ef-7a6a-5e91-9013-b72ed5b7b659	a869831f-0baa-5dcf-acf7-29b5bb7baeaf	INMETRO	BRASTEMP|BVG24|005221/2016|127 V	BRASTEMP	BVG24	inmetro_refrigerators	\N	636.00	\N	2026-10-15 20:58:22.480867+00	f	127 V	monovolt	127	127	53.0	kWh/mes
707fc999-8c82-5200-b3c1-b3cf7f20a328	17ec2033-1274-587c-9c08-03f16e660662	INMETRO	Midea|MRC12B1|001496/2017|127 V	Midea	MRC12B1	inmetro_refrigerators	\N	175.20	\N	2026-10-15 20:58:22.480867+00	f	127 V	monovolt	127	127	14.6	kWh/mes
709d4757-8534-57ba-8612-021ff2e7602f	a869831f-0baa-5dcf-acf7-29b5bb7baeaf	INMETRO	Philco|PFH205B|003272/2019|220 V	Philco	PFH205B	inmetro_refrigerators	\N	386.40	\N	2026-10-15 20:58:22.480867+00	f	220 V	monovolt	220	220	32.2	kWh/mes
709e0078-bc8f-502a-8e0f-45a588d02f27	b03224d6-390e-55a5-9ea8-93d8f62bc65c	INMETRO	CONSUL|CRD36|005217/2016|220 V	CONSUL	CRD36	inmetro_refrigerators	\N	522.00	\N	2026-10-15 20:58:22.480867+00	f	220 V	monovolt	220	220	43.5	kWh/mes
71ec8cdd-f916-50ee-971c-0a45b8b6477a	b03224d6-390e-55a5-9ea8-93d8f62bc65c	INMETRO	BERTAZZONI|REF90X|000222/2018|127 V	BERTAZZONI	REF90X	inmetro_refrigerators	\N	608.40	\N	2026-10-15 20:58:22.480867+00	f	127 V	monovolt	127	127	50.7	kWh/mes
720cae2b-fddb-5d00-bf8e-4b9364adc493	a869831f-0baa-5dcf-acf7-29b5bb7baeaf	INMETRO	Philco|PFH515B|002580/2017|220 V	Philco	PFH515B	inmetro_refrigerators	\N	768.00	\N	2026-10-15 20:58:22.480867+00	f	220 V	monovolt	220	220	64.0	kWh/mes
72f13259-2b37-52bc-98b4-d833283baced	b03224d6-390e-55a5-9ea8-93d8f62bc65c	INMETRO	Britânia|BRF533ID|002671/2020|220 V	Britânia	BRF533ID	inmetro_refrigerators	\N	528.00	\N	2026-10-15 20:58:22.480867+00	f	220 V	monovolt	220	220	44.0	kWh/mes
7323e80a-4c91-5057-955a-dc24c2d38177	b03224d6-390e-55a5-9ea8-93d8f62bc65c	INMETRO	BRASTEMP|BRM54|005218/2016|127 V	BRASTEMP	BRM54	inmetro_refrigerators	\N	684.00	\N	2026-10-15 20:58:22.480867+00	f	127 V	monovolt	127	127	57.0	kWh/mes
7363ebb5-6695-518a-a322-4d2d42f06ff9	b03224d6-390e-55a5-9ea8-93d8f62bc65c	INMETRO	CONSUL|CRE44|005218/2016|127 V	CONSUL	CRE44	inmetro_refrigerators	\N	696.00	\N	2026-10-15 20:58:22.480867+00	f	127 V	monovolt	127	127	58.0	kWh/mes
7367e702-8be4-564a-90f0-f08239b223e5	a869831f-0baa-5dcf-acf7-29b5bb7baeaf	INMETRO	EOS|EFH350X|003659/2020|127 V	EOS	EFH350X	inmetro_refrigerators	\N	444.00	\N	2026-10-15 20:58:22.480867+00	f	127 V	monovolt	127	127	37.0	kWh/mes
737c5f4e-6cee-59da-adba-988104ee3cde	b03224d6-390e-55a5-9ea8-93d8f62bc65c	INMETRO	Philco|PRF600I|003507/2020|127 V	Philco	PRF600I	inmetro_refrigerators	\N	588.00	\N	2026-10-15 20:58:22.480867+00	f	127 V	monovolt	127	127	49.0	kWh/mes
7452145e-6800-5e97-9045-cf0b14f14de4	b03224d6-390e-55a5-9ea8-93d8f62bc65c	INMETRO	Samsung|RL4363RBASL/BZ|001495/2017|220 V	Samsung	RL4363RBASL/BZ	inmetro_refrigerators	\N	462.00	\N	2026-10-15 20:58:22.480867+00	f	220 V	monovolt	220	220	38.5	kWh/mes
74d04b5d-cdb5-5627-b2df-51064aaf033f	17ec2033-1274-587c-9c08-03f16e660662	INMETRO	Philco|PFG50B|003271/2019|220 V	Philco	PFG50B	inmetro_refrigerators	\N	144.00	\N	2026-10-15 20:58:22.480867+00	f	220 V	monovolt	220	220	12.0	kWh/mes
7556d41b-0f51-5944-b884-770867a93f8d	b03224d6-390e-55a5-9ea8-93d8f62bc65c	INMETRO	Electrolux|DM83X_DM84X|005404/2016|127 V	Electrolux	DM83X_DM84X	inmetro_refrigerators	\N	900.00	\N	2026-10-15 20:58:22.480867+00	f	127 V	monovolt	127	127	75.0	kWh/mes
765464e9-5eb2-5a94-9267-4936ba9b2a8f	b03224d6-390e-55a5-9ea8-93d8f62bc65c	INMETRO	CONSUL|CRD49|005217/2016|127 V	CONSUL	CRD49	inmetro_refrigerators	\N	696.00	\N	2026-10-15 20:58:22.480867+00	f	127 V	monovolt	127	127	58.0	kWh/mes
766afe3c-3d07-560f-8362-83f1ad6d4a68	a869831f-0baa-5dcf-acf7-29b5bb7baeaf	INMETRO	Electrolux|FE18|005399/2016|127 V	Electrolux	FE18	inmetro_refrigerators	\N	501.60	\N	2026-10-15 20:58:22.480867+00	f	127 V	monovolt	127	127	41.8	kWh/mes
768bc911-48d2-5948-9dc3-b3d09e43f3e9	b03224d6-390e-55a5-9ea8-93d8f62bc65c	INMETRO	Electrolux|DFN39_DFX39_TF39_TF39S|005404/2016|127 V	Electrolux	DFN39_DFX39_TF39_TF39S	inmetro_refrigerators	\N	523.20	\N	2026-10-15 20:58:22.480867+00	f	127 V	monovolt	127	127	43.6	kWh/mes
76b5cc57-2abb-5cfb-a606-1f32940ca0bd	17ec2033-1274-587c-9c08-03f16e660662	INMETRO	Philco|PFG50P|007591/2016|127 V	Philco	PFG50P	inmetro_refrigerators	\N	204.00	\N	2026-10-15 20:58:22.480867+00	f	127 V	monovolt	127	127	17.0	kWh/mes
76b7934a-11f6-5fab-ad2d-bca3b6ed8d05	b03224d6-390e-55a5-9ea8-93d8f62bc65c	INMETRO	BRASTEMP|GRO80|005218/2016|127 V	BRASTEMP	GRO80	inmetro_refrigerators	\N	872.40	\N	2026-10-15 20:58:22.480867+00	f	127 V	monovolt	127	127	72.7	kWh/mes
7710cae6-8d4c-50cc-bb23-58f98568cf9a	a869831f-0baa-5dcf-acf7-29b5bb7baeaf	INMETRO	CONSUL|CVT10|005220/2016|220 V	CONSUL	CVT10	inmetro_refrigerators	\N	420.00	\N	2026-10-15 20:58:22.480867+00	f	220 V	monovolt	220	220	35.0	kWh/mes
7715f51b-fb4e-5ecf-8d19-370225eff60f	b03224d6-390e-55a5-9ea8-93d8f62bc65c	INMETRO	LG|GS65SDN / GS65SDN1|003968/2017|220 V	LG	GS65SDN / GS65SDN1	inmetro_refrigerators	\N	690.00	\N	2026-10-15 20:58:22.480867+00	f	220 V	monovolt	220	220	57.5	kWh/mes
77620208-8b2e-5d6d-876f-bea7964bf337	b03224d6-390e-55a5-9ea8-93d8f62bc65c	INMETRO	CONSUL|CRM43|005218/2016|220 V	CONSUL	CRM43	inmetro_refrigerators	\N	669.60	\N	2026-10-15 20:58:22.480867+00	f	220 V	monovolt	220	220	55.8	kWh/mes
78afe034-60e4-547d-a3c3-abe10b80b50f	b03224d6-390e-55a5-9ea8-93d8f62bc65c	INMETRO	Miele|KS 37472 iD|001051/2020|220 V	Miele	KS 37472 iD	inmetro_refrigerators	\N	187.20	\N	2026-10-15 20:58:22.480867+00	f	220 V	monovolt	220	220	15.6	kWh/mes
796c5269-cc75-583b-ad07-0d08d8ab93c4	b03224d6-390e-55a5-9ea8-93d8f62bc65c	INMETRO	Electrolux|DF80_DF80X_DF82_DF82X|005404/2016|127 V	Electrolux	DF80_DF80X_DF82_DF82X	inmetro_refrigerators	\N	852.00	\N	2026-10-15 20:58:22.480867+00	f	127 V	monovolt	127	127	71.0	kWh/mes
7a6e3186-4ce4-5127-99c0-846533a8bdd0	a869831f-0baa-5dcf-acf7-29b5bb7baeaf	INMETRO	Philco|PFZ330B|003272/2019|127 V	Philco	PFZ330B	inmetro_refrigerators	\N	430.80	\N	2026-10-15 20:58:22.480867+00	f	127 V	monovolt	127	127	35.9	kWh/mes
7a9aaed9-3c6f-55f7-8f76-b8f22cf92ad6	b03224d6-390e-55a5-9ea8-93d8f62bc65c	INMETRO	Electrolux|DFN41_DFX41|005404/2016|220 V	Electrolux	DFN41_DFX41	inmetro_refrigerators	\N	651.60	\N	2026-10-15 20:58:22.480867+00	f	220 V	monovolt	220	220	54.3	kWh/mes
7aeefe4c-0872-5c5a-b4eb-89b9c9d169b1	b03224d6-390e-55a5-9ea8-93d8f62bc65c	INMETRO	Samsung|RT46K6A4KS9/FZ|001495/2017|127 V	Samsung	RT46K6A4KS9/FZ	inmetro_refrigerators	\N	499.20	\N	2026-10-15 20:58:22.480867+00	f	127 V	monovolt	127	127	41.6	kWh/mes
7afa2c5d-ef74-54e2-be22-2ba743e314bb	b03224d6-390e-55a5-9ea8-93d8f62bc65c	INMETRO	BRASTEMP|BRA08|005222/2016|220 V	BRASTEMP	BRA08	inmetro_refrigerators	\N	210.00	\N	2026-10-15 20:58:22.480867+00	f	220 V	monovolt	220	220	17.5	kWh/mes
7b6cf550-7c7a-5c78-b43e-6c7498502f79	17ec2033-1274-587c-9c08-03f16e660662	INMETRO	Philco|PFG85PL|003271/2019|127 V	Philco	PFG85PL	inmetro_refrigerators	\N	148.80	\N	2026-10-15 20:58:22.480867+00	f	127 V	monovolt	127	127	12.4	kWh/mes
7b9ce849-bbe1-591b-86d5-ae3a50455e22	17ec2033-1274-587c-9c08-03f16e660662	INMETRO	Midea|MRC08|001496/2017|220 V	Midea	MRC08	inmetro_refrigerators	\N	156.00	\N	2026-10-15 20:58:22.480867+00	f	220 V	monovolt	220	220	13.0	kWh/mes
7be810de-5d92-5e2c-b540-bf9b27997139	a869831f-0baa-5dcf-acf7-29b5bb7baeaf	INMETRO	Electrolux|H330|004053/2020|127 V	Electrolux	H330	inmetro_refrigerators	\N	555.60	\N	2026-10-15 20:58:22.480867+00	f	127 V	monovolt	127	127	46.3	kWh/mes
7bfc5002-dba5-5c31-9e8b-5dfb7e040a7f	a869831f-0baa-5dcf-acf7-29b5bb7baeaf	INMETRO	EOS|EFH550XX|003659/2020|220 V	EOS	EFH550XX	inmetro_refrigerators	\N	733.20	\N	2026-10-15 20:58:22.480867+00	f	220 V	monovolt	220	220	61.1	kWh/mes
7c0c889a-2ed7-5b21-92b1-7f329d1de94c	17ec2033-1274-587c-9c08-03f16e660662	INMETRO	Philco|PFG95B|007591/2016|220 V	Philco	PFG95B	inmetro_refrigerators	\N	216.00	\N	2026-10-15 20:58:22.480867+00	f	220 V	monovolt	220	220	18.0	kWh/mes
7cb689a3-99a2-5ad6-a924-078082959ab9	b03224d6-390e-55a5-9ea8-93d8f62bc65c	INMETRO	CONSUL|CRA30|005222/2016|127 V	CONSUL	CRA30	inmetro_refrigerators	\N	291.60	\N	2026-10-15 20:58:22.480867+00	f	127 V	monovolt	127	127	24.3	kWh/mes
7d1fc571-df20-56c2-b6db-a81c5260ab68	b03224d6-390e-55a5-9ea8-93d8f62bc65c	INMETRO	Electrolux|DM85X_DM86X_DM86V|005404/2016|127 V	Electrolux	DM85X_DM86X_DM86V	inmetro_refrigerators	\N	828.00	\N	2026-10-15 20:58:22.480867+00	f	127 V	monovolt	127	127	69.0	kWh/mes
7d981482-17a6-5f61-b688-bc210aca30a3	b03224d6-390e-55a5-9ea8-93d8f62bc65c	INMETRO	Electrolux|RFE39|005397/2016|220 V	Electrolux	RFE39	inmetro_refrigerators	\N	450.00	\N	2026-10-15 20:58:22.480867+00	f	220 V	monovolt	220	220	37.5	kWh/mes
7dea7bab-6114-518d-aa7a-2606710739f4	b03224d6-390e-55a5-9ea8-93d8f62bc65c	INMETRO	CONSUL|CRM45|005218/2016|127 V	CONSUL	CRM45	inmetro_refrigerators	\N	630.00	\N	2026-10-15 20:58:22.480867+00	f	127 V	monovolt	127	127	52.5	kWh/mes
7e824366-3536-5701-bedf-b4f86b06c444	a869831f-0baa-5dcf-acf7-29b5bb7baeaf	INMETRO	Philco|H200L|002580/2017|127 V	Philco	H200L	inmetro_refrigerators	\N	414.00	\N	2026-10-15 20:58:22.480867+00	f	127 V	monovolt	127	127	34.5	kWh/mes
7ea0fe48-8ea8-584f-8d78-ab4f2ad2e2f5	b03224d6-390e-55a5-9ea8-93d8f62bc65c	INMETRO	TECNO|TR65FXDA|005435/2019|220 V	TECNO	TR65FXDA	inmetro_refrigerators	\N	518.40	\N	2026-10-15 20:58:22.480867+00	f	220 V	monovolt	220	220	43.2	kWh/mes
7f8e07ba-fdff-530b-8c6a-781dab38b908	b03224d6-390e-55a5-9ea8-93d8f62bc65c	INMETRO	BRASTEMP|BRE59|005218/2016|127 V	BRASTEMP	BRE59	inmetro_refrigerators	\N	804.00	\N	2026-10-15 20:58:22.480867+00	f	127 V	monovolt	127	127	67.0	kWh/mes
7fa5e76a-c4f1-5214-bbd9-05ef051ead31	b03224d6-390e-55a5-9ea8-93d8f62bc65c	INMETRO	BERTAZZONI|REF90PIXR|000222/2018|220 V	BERTAZZONI	REF90PIXR	inmetro_refrigerators	\N	469.20	\N	2026-10-15 20:58:22.480867+00	f	220 V	monovolt	220	220	39.1	kWh/mes
7fbbaa28-2dfd-529e-92b6-3e8ab626bef4	b03224d6-390e-55a5-9ea8-93d8f62bc65c	INMETRO	Miele|KFNS 37692 IDE|004923/2020|220 V	Miele	KFNS 37692 IDE	inmetro_refrigerators	\N	306.00	\N	2026-10-15 20:58:22.480867+00	f	220 V	monovolt	220	220	25.5	kWh/mes
7ff67020-89d1-5f4b-b505-4d9bcffa152b	b03224d6-390e-55a5-9ea8-93d8f62bc65c	INMETRO	Samsung|RF27T5501SG/BZ|000243/2019|220 V	Samsung	RF27T5501SG/BZ	inmetro_refrigerators	\N	720.00	\N	2026-10-15 20:58:22.480867+00	f	220 V	monovolt	220	220	60.0	kWh/mes
80059774-67a6-5358-8b77-5ed9a03c18a2	a869831f-0baa-5dcf-acf7-29b5bb7baeaf	INMETRO	Miele|F 2411 Vi 127 volts|001052/2020|127 V	Miele	F 2411 Vi 127 volts	inmetro_refrigerators	\N	426.00	\N	2026-10-15 20:58:22.480867+00	f	127 V	monovolt	127	127	35.5	kWh/mes
800e5e61-bca1-528e-957b-f14aea8b4a8c	b03224d6-390e-55a5-9ea8-93d8f62bc65c	INMETRO	Philco|PRF504ID|001056/2020|127 V	Philco	PRF504ID	inmetro_refrigerators	\N	612.00	\N	2026-10-15 20:58:22.480867+00	f	127 V	monovolt	127	127	51.0	kWh/mes
8075e128-36e8-5318-b0b7-1752058b6f8c	b03224d6-390e-55a5-9ea8-93d8f62bc65c	INMETRO	Midea|MD-RT453FGA041|002748/2020|127 V	Midea	MD-RT453FGA041	inmetro_refrigerators	\N	535.20	\N	2026-10-15 20:58:22.480867+00	f	127 V	monovolt	127	127	44.6	kWh/mes
81509440-3895-5237-862b-0fff8aed20ce	b03224d6-390e-55a5-9ea8-93d8f62bc65c	INMETRO	CONSUL|CRM43|005218/2016|127 V	CONSUL	CRM43	inmetro_refrigerators	\N	669.60	\N	2026-10-15 20:58:22.480867+00	f	127 V	monovolt	127	127	55.8	kWh/mes
817c2625-8080-59b7-8701-071b4da6f210	a869831f-0baa-5dcf-acf7-29b5bb7baeaf	INMETRO	Midea|RCFB32|003109/2016|220 V	Midea	RCFB32	inmetro_refrigerators	\N	430.80	\N	2026-10-15 20:58:22.480867+00	f	220 V	monovolt	220	220	35.9	kWh/mes
81f3ab54-e072-5d3a-a231-68716a2af67d	b03224d6-390e-55a5-9ea8-93d8f62bc65c	INMETRO	LG|GC-B659BSB / GC-B659BSB1|003968/2017|220 V	LG	GC-B659BSB / GC-B659BSB1	inmetro_refrigerators	\N	399.60	\N	2026-10-15 20:58:22.480867+00	f	220 V	monovolt	220	220	33.3	kWh/mes
8402e6e8-6b72-5a15-86a1-32727c37a4ba	b03224d6-390e-55a5-9ea8-93d8f62bc65c	INMETRO	Continental|TC44_TC44S|005404/2016|220 V	Continental	TC44_TC44S	inmetro_refrigerators	\N	663.60	\N	2026-10-15 20:58:22.480867+00	f	220 V	monovolt	220	220	55.3	kWh/mes
84097b51-fbbc-5bd3-8b39-aae31f05153e	b03224d6-390e-55a5-9ea8-93d8f62bc65c	INMETRO	Electrolux|DW44S|005404/2016|127 V	Electrolux	DW44S	inmetro_refrigerators	\N	675.60	\N	2026-10-15 20:58:22.480867+00	f	127 V	monovolt	127	127	56.3	kWh/mes
842d33c4-568e-536b-a368-27a9af3b4bfe	a869831f-0baa-5dcf-acf7-29b5bb7baeaf	INMETRO	Miele|F 2811 Vi 220 Volts|00579/2021|220 V	Miele	F 2811 Vi 220 Volts	inmetro_refrigerators	\N	546.00	\N	2026-10-15 20:58:22.480867+00	f	220 V	monovolt	220	220	45.5	kWh/mes
8589043f-8967-5c65-b207-6b5923057094	b03224d6-390e-55a5-9ea8-93d8f62bc65c	INMETRO	Philco|PRF411I|002671/2020|127 V	Philco	PRF411I	inmetro_refrigerators	\N	456.00	\N	2026-10-15 20:58:22.480867+00	f	127 V	monovolt	127	127	38.0	kWh/mes
8646e7b7-30a5-5d52-9569-afeb18624a1f	a869831f-0baa-5dcf-acf7-29b5bb7baeaf	INMETRO	Philco|PFH105B|003272/2019|220 V	Philco	PFH105B	inmetro_refrigerators	\N	276.00	\N	2026-10-15 20:58:22.480867+00	f	220 V	monovolt	220	220	23.0	kWh/mes
876eeff5-1ee0-5635-b1e8-81bda8bc9115	17ec2033-1274-587c-9c08-03f16e660662	INMETRO	Philco|PFG50B|007591/2016|127 V	Philco	PFG50B	inmetro_refrigerators	\N	204.00	\N	2026-10-15 20:58:22.480867+00	f	127 V	monovolt	127	127	17.0	kWh/mes
87cd5ea7-6249-5885-94ca-a4752461e577	b03224d6-390e-55a5-9ea8-93d8f62bc65c	INMETRO	Philco|PFG100RV|000963/2021|220 V	Philco	PFG100RV	inmetro_refrigerators	\N	266.40	\N	2026-10-15 20:58:22.480867+00	f	220 V	monovolt	220	220	22.2	kWh/mes
8817ede7-03ab-57a2-aa63-b4aeb5a93b8b	a869831f-0baa-5dcf-acf7-29b5bb7baeaf	INMETRO	Midea|CBA10|003109/2016|220 V	Midea	CBA10	inmetro_refrigerators	\N	210.00	\N	2026-10-15 20:58:22.480867+00	f	220 V	monovolt	220	220	17.5	kWh/mes
88ac3aee-82e1-5b64-b0b3-8a30e7ef22a3	b03224d6-390e-55a5-9ea8-93d8f62bc65c	INMETRO	Panasonic|NR-BB71|5576/2017|220 V	Panasonic	NR-BB71	inmetro_refrigerators	\N	490.80	\N	2026-10-15 20:58:22.480867+00	f	220 V	monovolt	220	220	40.9	kWh/mes
89168df0-b6c1-5cd7-9d7c-8d17994663b6	b03224d6-390e-55a5-9ea8-93d8f62bc65c	INMETRO	LG|GT44BPP / GT44BPP1|003968/2017|127 V	LG	GT44BPP / GT44BPP1	inmetro_refrigerators	\N	415.20	\N	2026-10-15 20:58:22.480867+00	f	127 V	monovolt	127	127	34.6	kWh/mes
8a3e2823-a90a-563a-a833-d9d0aee9cf2e	b03224d6-390e-55a5-9ea8-93d8f62bc65c	INMETRO	LG|GC-L247SLUV / GC-L247SLU1|003968/2017|220 V	LG	GC-L247SLUV / GC-L247SLU1	inmetro_refrigerators	\N	690.00	\N	2026-10-15 20:58:22.480867+00	f	220 V	monovolt	220	220	57.5	kWh/mes
8cbcdbdb-c270-554f-8e9c-2cd08631f1c9	b03224d6-390e-55a5-9ea8-93d8f62bc65c	INMETRO	Samsung|RF23R6201SR/AZ|007317/2017|127 V	Samsung	RF23R6201SR/AZ	inmetro_refrigerators	\N	720.00	\N	2026-10-15 20:58:22.480867+00	f	127 V	monovolt	127	127	60.0	kWh/mes
8dbbd82b-cd09-5686-976d-d9ee789a4404	17ec2033-1274-587c-9c08-03f16e660662	INMETRO	Midea|MRC10B1|001496/2017|127 V	Midea	MRC10B1	inmetro_refrigerators	\N	170.40	\N	2026-10-15 20:58:22.480867+00	f	127 V	monovolt	127	127	14.2	kWh/mes
8de3e9e2-eb79-5a7f-bec5-bf154a33462d	b03224d6-390e-55a5-9ea8-93d8f62bc65c	INMETRO	Gorenje|ONR192BK, NRK6192UX|002863/2017|220 V	Gorenje	ONR192BK, NRK6192UX	inmetro_refrigerators	\N	350.40	\N	2026-10-15 20:58:22.480867+00	f	220 V	monovolt	220	220	29.2	kWh/mes
8e2088b2-f0a9-5553-90d3-f4400bf1c860	b03224d6-390e-55a5-9ea8-93d8f62bc65c	INMETRO	BERTAZZONI|REF75PIXR|000222/2018|127 V	BERTAZZONI	REF75PIXR	inmetro_refrigerators	\N	447.60	\N	2026-10-15 20:58:22.480867+00	f	127 V	monovolt	127	127	37.3	kWh/mes
8e480ce0-3aac-5e85-b55c-9dda885b5330	17ec2033-1274-587c-9c08-03f16e660662	INMETRO	Philco|PFG90I|007591/2016|220 V	Philco	PFG90I	inmetro_refrigerators	\N	216.00	\N	2026-10-15 20:58:22.480867+00	f	220 V	monovolt	220	220	18.0	kWh/mes
8ead46ea-69a9-5a25-b378-ab97f31059a3	17ec2033-1274-587c-9c08-03f16e660662	INMETRO	Britânia|BFG85B|003271/2019|220 V	Britânia	BFG85B	inmetro_refrigerators	\N	145.20	\N	2026-10-15 20:58:22.480867+00	f	220 V	monovolt	220	220	12.1	kWh/mes
8fb749b6-8f95-5a93-af2c-f9307f4378c8	a869831f-0baa-5dcf-acf7-29b5bb7baeaf	INMETRO	Philco|PFH205B|003272/2019|127 V	Philco	PFH205B	inmetro_refrigerators	\N	414.00	\N	2026-10-15 20:58:22.480867+00	f	127 V	monovolt	127	127	34.5	kWh/mes
8fbcf3e3-bdf3-5598-8cf8-5eca3ce28e50	a869831f-0baa-5dcf-acf7-29b5bb7baeaf	INMETRO	Philco|PFV205B|004608/2020|220 V	Philco	PFV205B	inmetro_refrigerators	\N	384.00	\N	2026-10-15 20:58:22.480867+00	f	220 V	monovolt	220	220	32.0	kWh/mes
9000c971-4701-524a-9dd2-403ae7c055dc	17ec2033-1274-587c-9c08-03f16e660662	INMETRO	Galanz|GFb12C01A-Ix127\nGFb12C01A-Pt127\nGFb12C01A-Br127\nGFb12C01A-Ix220\nGFb12C01A-Pt220\nGFb12C01A-Br220|004319/2020|127 V	Galanz	GFb12C01A-Ix127\nGFb12C01A-Pt127\nGFb12C01A-Br127\nGFb12C01A-Ix220\nGFb12C01A-Pt220\nGFb12C01A-Br220	inmetro_refrigerators	\N	289.20	\N	2026-10-15 20:58:22.480867+00	f	127 V	monovolt	127	127	24.1	kWh/mes
90ecaa9b-6246-5ade-bc63-a76863e06b37	a869831f-0baa-5dcf-acf7-29b5bb7baeaf	INMETRO	CONSUL|CHB42|005219/2016|127 V	CONSUL	CHB42	inmetro_refrigerators	\N	699.60	\N	2026-10-15 20:58:22.480867+00	f	127 V	monovolt	127	127	58.3	kWh/mes
911a359e-2ca6-5307-99c1-c60223721ee5	b03224d6-390e-55a5-9ea8-93d8f62bc65c	INMETRO	CONSUL|CRM50|005218/2016|127 V	CONSUL	CRM50	inmetro_refrigerators	\N	672.00	\N	2026-10-15 20:58:22.480867+00	f	127 V	monovolt	127	127	56.0	kWh/mes
912bae24-89cb-5df9-adb4-6cbbc1eb9621	b03224d6-390e-55a5-9ea8-93d8f62bc65c	INMETRO	LG|GC-L228FTLK / GC-L228FTL1|003968/2017|220 V	LG	GC-L228FTLK / GC-L228FTL1	inmetro_refrigerators	\N	684.00	\N	2026-10-15 20:58:22.480867+00	f	220 V	monovolt	220	220	57.0	kWh/mes
916aa79e-0e3b-5f0d-8348-004aaafe52c7	b03224d6-390e-55a5-9ea8-93d8f62bc65c	INMETRO	Gorenje|RI5182A1|005038/2019|220 V	Gorenje	RI5182A1	inmetro_refrigerators	\N	189.60	\N	2026-10-15 20:58:22.480867+00	f	220 V	monovolt	220	220	15.8	kWh/mes
9256d900-ff4d-50b6-a10d-3e9bfc34a8bf	b03224d6-390e-55a5-9ea8-93d8f62bc65c	INMETRO	Electrolux|IF55_IF55S_IF55B|005404/2016|220 V	Electrolux	IF55_IF55S_IF55B	inmetro_refrigerators	\N	423.60	\N	2026-10-15 20:58:22.480867+00	f	220 V	monovolt	220	220	35.3	kWh/mes
926f2ab3-4e2f-5222-b4aa-75fd01c70f3a	a869831f-0baa-5dcf-acf7-29b5bb7baeaf	INMETRO	Philco|PFV205I|004608/2020|220 V	Philco	PFV205I	inmetro_refrigerators	\N	384.00	\N	2026-10-15 20:58:22.480867+00	f	220 V	monovolt	220	220	32.0	kWh/mes
93a2a597-e2ef-5a35-b0e5-11e91f27df7b	a869831f-0baa-5dcf-acf7-29b5bb7baeaf	INMETRO	Midea|RCFB31|003109/2016|127 V	Midea	RCFB31	inmetro_refrigerators	\N	492.00	\N	2026-10-15 20:58:22.480867+00	f	127 V	monovolt	127	127	41.0	kWh/mes
93eae7e4-6f34-5f91-a0fb-53404b7c521e	b03224d6-390e-55a5-9ea8-93d8f62bc65c	INMETRO	Philco|PRF503TI|003507/2020|220 V	Philco	PRF503TI	inmetro_refrigerators	\N	432.00	\N	2026-10-15 20:58:22.480867+00	f	220 V	monovolt	220	220	36.0	kWh/mes
94d10d7b-58b2-5ca1-a3ce-fe2df6555ea2	a869831f-0baa-5dcf-acf7-29b5bb7baeaf	INMETRO	CONSUL|CVU26Z|005220/2016|220 V	CONSUL	CVU26Z	inmetro_refrigerators	\N	470.40	\N	2026-10-15 20:58:22.480867+00	f	220 V	monovolt	220	220	39.2	kWh/mes
9510561e-2d1f-579e-b017-8fcc45340fa2	17ec2033-1274-587c-9c08-03f16e660662	INMETRO	Philco|PFG50B|003271/2019|127 V	Philco	PFG50B	inmetro_refrigerators	\N	141.60	\N	2026-10-15 20:58:22.480867+00	f	127 V	monovolt	127	127	11.8	kWh/mes
959986dd-24a6-5069-b2b3-3eeb9b289729	17ec2033-1274-587c-9c08-03f16e660662	INMETRO	Philco|PFG107RV|001955/2017|220 V	Philco	PFG107RV	inmetro_refrigerators	\N	210.00	\N	2026-10-15 20:58:22.480867+00	f	220 V	monovolt	220	220	17.5	kWh/mes
96f9b171-d453-590b-841f-5eeb61430361	17ec2033-1274-587c-9c08-03f16e660662	INMETRO	Britânia|BFG50B|007591/2016|127 V	Britânia	BFG50B	inmetro_refrigerators	\N	204.00	\N	2026-10-15 20:58:22.480867+00	f	127 V	monovolt	127	127	17.0	kWh/mes
9772d009-6d5d-5962-8cca-ed6a7e24db5e	b03224d6-390e-55a5-9ea8-93d8f62bc65c	INMETRO	Samsung|RS65R5691M9/BZ|004878/2019|220 V	Samsung	RS65R5691M9/BZ	inmetro_refrigerators	\N	710.40	\N	2026-10-15 20:58:22.480867+00	f	220 V	monovolt	220	220	59.2	kWh/mes
98811008-2177-548a-8239-e15027f04a03	b03224d6-390e-55a5-9ea8-93d8f62bc65c	INMETRO	CONSUL|CRM54|005218/2016|127 V	CONSUL	CRM54	inmetro_refrigerators	\N	672.00	\N	2026-10-15 20:58:22.480867+00	f	127 V	monovolt	127	127	56.0	kWh/mes
98a5d7b9-4975-5a2d-a117-4cd0efcea6ae	b03224d6-390e-55a5-9ea8-93d8f62bc65c	INMETRO	Philco|PRF406I|008370/2019|127 V	Philco	PRF406I	inmetro_refrigerators	\N	480.00	\N	2026-10-15 20:58:22.480867+00	f	127 V	monovolt	127	127	40.0	kWh/mes
98b6f4e2-f2c6-5c83-b5c9-1a980acb8df4	a869831f-0baa-5dcf-acf7-29b5bb7baeaf	INMETRO	Philco|PFH260B|002580/2017|127 V	Philco	PFH260B	inmetro_refrigerators	\N	456.00	\N	2026-10-15 20:58:22.480867+00	f	127 V	monovolt	127	127	38.0	kWh/mes
98d16cec-a1c8-561a-8747-161a1253fcaa	b03224d6-390e-55a5-9ea8-93d8f62bc65c	INMETRO	Crissair|RFD 01|004457/2018|127 V	Crissair	RFD 01	inmetro_refrigerators	\N	673.20	\N	2026-10-15 20:58:22.480867+00	f	127 V	monovolt	127	127	56.1	kWh/mes
98f6872f-74aa-5d06-9c7b-4f305a39bbd7	b03224d6-390e-55a5-9ea8-93d8f62bc65c	INMETRO	TECNO|TR14GXDA|004358/2020|220 V	TECNO	TR14GXDA	inmetro_refrigerators	\N	284.40	\N	2026-10-15 20:58:22.480867+00	f	220 V	monovolt	220	220	23.7	kWh/mes
9964b28e-db1c-5976-bbd1-bf1516262fb9	17ec2033-1274-587c-9c08-03f16e660662	INMETRO	Philco|PFG85ICE|003271/2019|220 V	Philco	PFG85ICE	inmetro_refrigerators	\N	145.20	\N	2026-10-15 20:58:22.480867+00	f	220 V	monovolt	220	220	12.1	kWh/mes
99c36853-f9c3-5c85-8b4d-c82b78687be0	a869831f-0baa-5dcf-acf7-29b5bb7baeaf	INMETRO	Britânia|BFH162B|003272/2019|220 V	Britânia	BFH162B	inmetro_refrigerators	\N	309.60	\N	2026-10-15 20:58:22.480867+00	f	220 V	monovolt	220	220	25.8	kWh/mes
9a929374-5b6d-5118-b341-8c31a9114c54	b03224d6-390e-55a5-9ea8-93d8f62bc65c	INMETRO	Electrolux|TW42S|005404/2016|127 V	Electrolux	TW42S	inmetro_refrigerators	\N	636.00	\N	2026-10-15 20:58:22.480867+00	f	127 V	monovolt	127	127	53.0	kWh/mes
9a986fc5-07f6-545a-bb64-882bb07d131e	a869831f-0baa-5dcf-acf7-29b5bb7baeaf	INMETRO	Miele|F 2911 Vi 127 Volts|001052/2020|127 V	Miele	F 2911 Vi 127 Volts	inmetro_refrigerators	\N	601.20	\N	2026-10-15 20:58:22.480867+00	f	127 V	monovolt	127	127	50.1	kWh/mes
9ac7f424-ced5-58b4-9a68-8b779e7b7c69	17ec2033-1274-587c-9c08-03f16e660662	INMETRO	Electrolux|BEER2|006524/2018|220 V	Electrolux	BEER2	inmetro_refrigerators	\N	204.00	\N	2026-10-15 20:58:22.480867+00	f	220 V	monovolt	220	220	17.0	kWh/mes
9b30f219-aec3-5c7d-a7bd-a09c70942bed	b03224d6-390e-55a5-9ea8-93d8f62bc65c	INMETRO	Philco|PFG121RV|000963/2021|220 V	Philco	PFG121RV	inmetro_refrigerators	\N	234.00	\N	2026-10-15 20:58:22.480867+00	f	220 V	monovolt	220	220	19.5	kWh/mes
9b4f120f-bc6d-5215-a509-f4d397c09823	a869831f-0baa-5dcf-acf7-29b5bb7baeaf	INMETRO	Viking Range|VCFB5303 / FDFB5303|001954/2017|127 V	Viking Range	VCFB5303 / FDFB5303	inmetro_refrigerators	\N	1296.00	\N	2026-10-15 20:58:22.480867+00	f	127 V	monovolt	127	127	108.0	kWh/mes
9b6f2709-ccdf-512f-8afd-50b33eb82f57	b03224d6-390e-55a5-9ea8-93d8f62bc65c	INMETRO	Samsung|RF23R6301SR/BZ|007317/2017|220 V	Samsung	RF23R6301SR/BZ	inmetro_refrigerators	\N	840.00	\N	2026-10-15 20:58:22.480867+00	f	220 V	monovolt	220	220	70.0	kWh/mes
9b75919c-d21e-5bb9-86d8-40a5bfaf7361	b03224d6-390e-55a5-9ea8-93d8f62bc65c	INMETRO	Elettromec|RF-BF-360-VT-2HMC / RF-BF-360-XX-2HMC|001451/2018|220 V	Elettromec	RF-BF-360-VT-2HMC / RF-BF-360-XX-2HMC	inmetro_refrigerators	\N	292.80	\N	2026-10-15 20:58:22.480867+00	f	220 V	monovolt	220	220	24.4	kWh/mes
9be31811-3619-5aa7-ac54-a853f242de65	b03224d6-390e-55a5-9ea8-93d8f62bc65c	INMETRO	LG|GT51BPP / GT51BPP1|006368/2019|127 V	LG	GT51BPP / GT51BPP1	inmetro_refrigerators	\N	522.00	\N	2026-10-15 20:58:22.480867+00	f	127 V	monovolt	127	127	43.5	kWh/mes
9bfb3c55-f096-561b-9661-fe7794d297c2	17ec2033-1274-587c-9c08-03f16e660662	INMETRO	Britânia|BFG85B|003271/2019|127 V	Britânia	BFG85B	inmetro_refrigerators	\N	148.80	\N	2026-10-15 20:58:22.480867+00	f	127 V	monovolt	127	127	12.4	kWh/mes
9c8a7f47-ae96-59dd-b491-e6cbedb8a940	b03224d6-390e-55a5-9ea8-93d8f62bc65c	INMETRO	Toshiba|GR-RF646WEPMA|002669/2020|127 V	Toshiba	GR-RF646WEPMA	inmetro_refrigerators	\N	718.80	\N	2026-10-15 20:58:22.480867+00	f	127 V	monovolt	127	127	59.9	kWh/mes
9cacfc52-dba1-5977-bf0a-bd9dc27a5ee1	b03224d6-390e-55a5-9ea8-93d8f62bc65c	INMETRO	CONSUL|CRM52|005218/2016|220 V	CONSUL	CRM52	inmetro_refrigerators	\N	630.00	\N	2026-10-15 20:58:22.480867+00	f	220 V	monovolt	220	220	52.5	kWh/mes
9cdc39d0-bb53-5edf-be21-eb42dc981916	17ec2033-1274-587c-9c08-03f16e660662	INMETRO	Britânia|BFG50B|003271/2019|220 V	Britânia	BFG50B	inmetro_refrigerators	\N	144.00	\N	2026-10-15 20:58:22.480867+00	f	220 V	monovolt	220	220	12.0	kWh/mes
9d275505-ff30-5c53-aac0-cd3199635f65	a869831f-0baa-5dcf-acf7-29b5bb7baeaf	INMETRO	CONSUL|CHA31|005219/2016|127 V	CONSUL	CHA31	inmetro_refrigerators	\N	554.40	\N	2026-10-15 20:58:22.480867+00	f	127 V	monovolt	127	127	46.2	kWh/mes
9d616033-a31d-57ea-91be-a638e538b0ae	17ec2033-1274-587c-9c08-03f16e660662	INMETRO	Philco|PFG112B|001955/2017|127 V	Philco	PFG112B	inmetro_refrigerators	\N	198.00	\N	2026-10-15 20:58:22.480867+00	f	127 V	monovolt	127	127	16.5	kWh/mes
9f2a935f-27a4-5116-b4c8-e79cbbdb960c	b03224d6-390e-55a5-9ea8-93d8f62bc65c	INMETRO	Philco|PRF520DI|008370/2019|127 V	Philco	PRF520DI	inmetro_refrigerators	\N	715.20	\N	2026-10-15 20:58:22.480867+00	f	127 V	monovolt	127	127	59.6	kWh/mes
9f6e08e8-3bff-590b-95bf-bacf0911e766	b03224d6-390e-55a5-9ea8-93d8f62bc65c	INMETRO	Samsung|RF59A7011SR/BZ|007317/2017|220 V	Samsung	RF59A7011SR/BZ	inmetro_refrigerators	\N	720.00	\N	2026-10-15 20:58:22.480867+00	f	220 V	monovolt	220	220	60.0	kWh/mes
9fc1f819-4b30-5fc4-802c-5f16b099f55a	a869831f-0baa-5dcf-acf7-29b5bb7baeaf	INMETRO	CONSUL|CVT10|005220/2016|127 V	CONSUL	CVT10	inmetro_refrigerators	\N	420.00	\N	2026-10-15 20:58:22.480867+00	f	127 V	monovolt	127	127	35.0	kWh/mes
9fe88607-2f87-52ea-a7dc-f39613cb2ed7	17ec2033-1274-587c-9c08-03f16e660662	INMETRO	Britânia|BFG85PL|003271/2019|127 V	Britânia	BFG85PL	inmetro_refrigerators	\N	148.80	\N	2026-10-15 20:58:22.480867+00	f	127 V	monovolt	127	127	12.4	kWh/mes
a080e815-bb52-5c64-9acb-f318d93a4ad7	b03224d6-390e-55a5-9ea8-93d8f62bc65c	INMETRO	BRASTEMP|BRM56|005218/2016|220 V	BRASTEMP	BRM56	inmetro_refrigerators	\N	780.00	\N	2026-10-15 20:58:22.480867+00	f	220 V	monovolt	220	220	65.0	kWh/mes
a1625061-8f16-51d1-848e-a5043600ba41	a869831f-0baa-5dcf-acf7-29b5bb7baeaf	INMETRO	Midea|CBA10|003109/2016|127 V	Midea	CBA10	inmetro_refrigerators	\N	249.60	\N	2026-10-15 20:58:22.480867+00	f	127 V	monovolt	127	127	20.8	kWh/mes
a18498fd-bbeb-5be3-bd97-c1c16ec39720	a869831f-0baa-5dcf-acf7-29b5bb7baeaf	INMETRO	Miele|F 2411 Vi 220 Volts|003476/2021|220 V	Miele	F 2411 Vi 220 Volts	inmetro_refrigerators	\N	397.20	\N	2026-10-15 20:58:22.480867+00	f	220 V	monovolt	220	220	33.1	kWh/mes
a1949539-ad7c-50e7-b072-88ac8d38790f	a869831f-0baa-5dcf-acf7-29b5bb7baeaf	INMETRO	Philco|PFV205B|004608/2020|127 V	Philco	PFV205B	inmetro_refrigerators	\N	384.00	\N	2026-10-15 20:58:22.480867+00	f	127 V	monovolt	127	127	32.0	kWh/mes
a1ac7e71-8820-53b9-8f3c-bf974d22fc4f	b03224d6-390e-55a5-9ea8-93d8f62bc65c	INMETRO	Esmaltec|RCD38|002252/2017|220 V	Esmaltec	RCD38	inmetro_refrigerators	\N	492.00	\N	2026-10-15 20:58:22.480867+00	f	220 V	monovolt	220	220	41.0	kWh/mes
a42855d8-ced0-5aa8-9982-6b511257e48b	b03224d6-390e-55a5-9ea8-93d8f62bc65c	INMETRO	BRASTEMP|BRE80|005218/2016|220 V	BRASTEMP	BRE80	inmetro_refrigerators	\N	816.00	\N	2026-10-15 20:58:22.480867+00	f	220 V	monovolt	220	220	68.0	kWh/mes
a4bb0cef-6572-51f9-aff3-cf225c4c724e	a869831f-0baa-5dcf-acf7-29b5bb7baeaf	INMETRO	Electrolux|H222|005396/2016|127 V	Electrolux	H222	inmetro_refrigerators	\N	408.00	\N	2026-10-15 20:58:22.480867+00	f	127 V	monovolt	127	127	34.0	kWh/mes
a547a9e2-a961-5830-a205-582974562cb8	b03224d6-390e-55a5-9ea8-93d8f62bc65c	INMETRO	CONSUL|CRC08|005222/2016|127 V	CONSUL	CRC08	inmetro_refrigerators	\N	210.00	\N	2026-10-15 20:58:22.480867+00	f	127 V	monovolt	127	127	17.5	kWh/mes
a562137e-1b2c-5849-8683-a29f8958bcf3	b03224d6-390e-55a5-9ea8-93d8f62bc65c	INMETRO	BRASTEMP|BRA08|005222/2016|127 V	BRASTEMP	BRA08	inmetro_refrigerators	\N	210.00	\N	2026-10-15 20:58:22.480867+00	f	127 V	monovolt	127	127	17.5	kWh/mes
a56801d0-76c0-55cb-8456-2e1e8bece0dc	b03224d6-390e-55a5-9ea8-93d8f62bc65c	INMETRO	BERTAZZONI|REF75PRR|000222/2018|127 V	BERTAZZONI	REF75PRR	inmetro_refrigerators	\N	447.60	\N	2026-10-15 20:58:22.480867+00	f	127 V	monovolt	127	127	37.3	kWh/mes
a5f6a26a-a184-5ad2-9702-3df2a1a9cc84	a869831f-0baa-5dcf-acf7-29b5bb7baeaf	INMETRO	Philco|PFH440B|003272/2019|127 V	Philco	PFH440B	inmetro_refrigerators	\N	429.60	\N	2026-10-15 20:58:22.480867+00	f	127 V	monovolt	127	127	35.8	kWh/mes
a66aa673-59e6-56ab-92c4-978181a4fa0f	17ec2033-1274-587c-9c08-03f16e660662	INMETRO	Britânia|BFG111B|003271/2019|127 V	Britânia	BFG111B	inmetro_refrigerators	\N	198.00	\N	2026-10-15 20:58:22.480867+00	f	127 V	monovolt	127	127	16.5	kWh/mes
a68f393f-3be8-5662-be3c-947bad178608	b03224d6-390e-55a5-9ea8-93d8f62bc65c	INMETRO	BERTAZZONI|REF90PRL|000222/2018|127 V	BERTAZZONI	REF90PRL	inmetro_refrigerators	\N	469.20	\N	2026-10-15 20:58:22.480867+00	f	127 V	monovolt	127	127	39.1	kWh/mes
a6c5fe9d-f216-5c99-aac8-f7c850213335	b03224d6-390e-55a5-9ea8-93d8f62bc65c	INMETRO	Electrolux|DQ90X|000514/2018|220 V	Electrolux	DQ90X	inmetro_refrigerators	\N	750.00	\N	2026-10-15 20:58:22.480867+00	f	220 V	monovolt	220	220	62.5	kWh/mes
a749cdf0-741d-5e92-9a9b-2a69648ac29c	b03224d6-390e-55a5-9ea8-93d8f62bc65c	INMETRO	Crissair|RFD 02|004457/2018|220 V	Crissair	RFD 02	inmetro_refrigerators	\N	736.80	\N	2026-10-15 20:58:22.480867+00	f	220 V	monovolt	220	220	61.4	kWh/mes
a8f96dbc-87a9-5b36-8017-13f33f6292ae	17ec2033-1274-587c-9c08-03f16e660662	INMETRO	Philco|PFG87B|001955/2017|220 V	Philco	PFG87B	inmetro_refrigerators	\N	177.60	\N	2026-10-15 20:58:22.480867+00	f	220 V	monovolt	220	220	14.8	kWh/mes
a8fc0848-07e7-5a95-afe1-30d42961ebf6	17ec2033-1274-587c-9c08-03f16e660662	INMETRO	Philco|PH85PR|007591/2016|127 V	Philco	PH85PR	inmetro_refrigerators	\N	210.00	\N	2026-10-15 20:58:22.480867+00	f	127 V	monovolt	127	127	17.5	kWh/mes
aa924aac-7d27-5a58-bbfd-bbb3ca7a0e95	b03224d6-390e-55a5-9ea8-93d8f62bc65c	INMETRO	BRASTEMP|BRM44|005218/2016|220 V	BRASTEMP	BRM44	inmetro_refrigerators	\N	648.00	\N	2026-10-15 20:58:22.480867+00	f	220 V	monovolt	220	220	54.0	kWh/mes
ab3dc0ba-c9c5-541c-96a0-babd2a1aab78	b03224d6-390e-55a5-9ea8-93d8f62bc65c	INMETRO	Miele|K 2801 Vi 220 Volts|001592/2021|220 V	Miele	K 2801 Vi 220 Volts	inmetro_refrigerators	\N	218.40	\N	2026-10-15 20:58:22.480867+00	f	220 V	monovolt	220	220	18.2	kWh/mes
ab83d97e-9830-570f-9695-c2ea1155bece	17ec2033-1274-587c-9c08-03f16e660662	INMETRO	Philco|PFG111B|003271/2019|127 V	Philco	PFG111B	inmetro_refrigerators	\N	198.00	\N	2026-10-15 20:58:22.480867+00	f	127 V	monovolt	127	127	16.5	kWh/mes
ab8e599d-4af8-51d9-93d1-4506dc990447	b03224d6-390e-55a5-9ea8-93d8f62bc65c	INMETRO	Philco|PRF411I|002671/2020|220 V	Philco	PRF411I	inmetro_refrigerators	\N	504.00	\N	2026-10-15 20:58:22.480867+00	f	220 V	monovolt	220	220	42.0	kWh/mes
ac4bcedf-9e53-53b6-bf3e-81780c65edbf	b03224d6-390e-55a5-9ea8-93d8f62bc65c	INMETRO	Elettromec|RF-FD-531-XX-2HSA|004429/2016|220 V	Elettromec	RF-FD-531-XX-2HSA	inmetro_refrigerators	\N	559.20	\N	2026-10-15 20:58:22.480867+00	f	220 V	monovolt	220	220	46.6	kWh/mes
aceb0691-820f-50cb-b075-348938118457	b03224d6-390e-55a5-9ea8-93d8f62bc65c	INMETRO	Philco|PRF510I|004318/2020|127 V	Philco	PRF510I	inmetro_refrigerators	\N	756.00	\N	2026-10-15 20:58:22.480867+00	f	127 V	monovolt	127	127	63.0	kWh/mes
ad1fd71d-73b7-597e-a531-16584399887b	b03224d6-390e-55a5-9ea8-93d8f62bc65c	INMETRO	Electrolux|TW42S|005404/2016|220 V	Electrolux	TW42S	inmetro_refrigerators	\N	636.00	\N	2026-10-15 20:58:22.480867+00	f	220 V	monovolt	220	220	53.0	kWh/mes
ae2e87b4-1d40-5d65-9b28-ff48fcac036e	b03224d6-390e-55a5-9ea8-93d8f62bc65c	INMETRO	Esmaltec|ROC35R|002251/2017|127 V	Esmaltec	ROC35R	inmetro_refrigerators	\N	262.80	\N	2026-10-15 20:58:22.480867+00	f	127 V	monovolt	127	127	21.9	kWh/mes
aea1829d-b54c-5c43-8dc7-19a4c69e3810	b03224d6-390e-55a5-9ea8-93d8f62bc65c	INMETRO	Electrolux|RE31|005401/2016|220 V	Electrolux	RE31	inmetro_refrigerators	\N	279.60	\N	2026-10-15 20:58:22.480867+00	f	220 V	monovolt	220	220	23.3	kWh/mes
b0903c47-82eb-5abd-9f72-49ac9296a692	b03224d6-390e-55a5-9ea8-93d8f62bc65c	INMETRO	Electrolux|DC51_DC51X|005402/2016|220 V	Electrolux	DC51_DC51X	inmetro_refrigerators	\N	705.60	\N	2026-10-15 20:58:22.480867+00	f	220 V	monovolt	220	220	58.8	kWh/mes
b0e79eab-c826-556e-9b47-079ab39cb913	b03224d6-390e-55a5-9ea8-93d8f62bc65c	INMETRO	Samsung|RT46K6A4KBS/FZ|001495/2017|127 V	Samsung	RT46K6A4KBS/FZ	inmetro_refrigerators	\N	434.40	\N	2026-10-15 20:58:22.480867+00	f	127 V	monovolt	127	127	36.2	kWh/mes
b147279e-cef3-531b-a8f0-d2fe4aee4190	17ec2033-1274-587c-9c08-03f16e660662	INMETRO	Philco|PH85N|007591/2016|220 V	Philco	PH85N	inmetro_refrigerators	\N	210.00	\N	2026-10-15 20:58:22.480867+00	f	220 V	monovolt	220	220	17.5	kWh/mes
b1c1396d-18a5-5a64-a13a-e38c5996dff7	b03224d6-390e-55a5-9ea8-93d8f62bc65c	INMETRO	Panasonic|NR-BT55|5576/2017|220 V	Panasonic	NR-BT55	inmetro_refrigerators	\N	468.00	\N	2026-10-15 20:58:22.480867+00	f	220 V	monovolt	220	220	39.0	kWh/mes
b2698f5e-df40-5038-92c0-3c0668cc95fd	a869831f-0baa-5dcf-acf7-29b5bb7baeaf	INMETRO	EOS|EFH150X|003659/2020|220 V	EOS	EFH150X	inmetro_refrigerators	\N	259.20	\N	2026-10-15 20:58:22.480867+00	f	220 V	monovolt	220	220	21.6	kWh/mes
b2b84a97-b613-58a7-b165-29aec80d459e	b03224d6-390e-55a5-9ea8-93d8f62bc65c	INMETRO	BRASTEMP|BRS75|005218/2016|127 V	BRASTEMP	BRS75	inmetro_refrigerators	\N	864.00	\N	2026-10-15 20:58:22.480867+00	f	127 V	monovolt	127	127	72.0	kWh/mes
b2e9e9d8-19bd-5fa5-9cf6-b63f54b04f61	b03224d6-390e-55a5-9ea8-93d8f62bc65c	INMETRO	Esmaltec|ROC31|002251/2017|127 V	Esmaltec	ROC31	inmetro_refrigerators	\N	286.80	\N	2026-10-15 20:58:22.480867+00	f	127 V	monovolt	127	127	23.9	kWh/mes
b4d94459-dd77-5809-b8ab-7e012d7a13f2	b03224d6-390e-55a5-9ea8-93d8f62bc65c	INMETRO	Philco|PRF533I|002671/2020|220 V	Philco	PRF533I	inmetro_refrigerators	\N	504.00	\N	2026-10-15 20:58:22.480867+00	f	220 V	monovolt	220	220	42.0	kWh/mes
b54f11a6-6629-5066-af8c-6deee7e35f4a	b03224d6-390e-55a5-9ea8-93d8f62bc65c	INMETRO	LG|GR-X228NMSM / GR-X228NMS1|005754/2019|127 V	LG	GR-X228NMSM / GR-X228NMS1	inmetro_refrigerators	\N	842.40	\N	2026-10-15 20:58:22.480867+00	f	127 V	monovolt	127	127	70.2	kWh/mes
b63e3ffb-e40c-5b5a-83eb-ddce9d77efb8	b03224d6-390e-55a5-9ea8-93d8f62bc65c	INMETRO	BERTAZZONI|REF90PIXL|000222/2018|127 V	BERTAZZONI	REF90PIXL	inmetro_refrigerators	\N	469.20	\N	2026-10-15 20:58:22.480867+00	f	127 V	monovolt	127	127	39.1	kWh/mes
b7b39f11-4f9b-5979-8803-f09ea584acb9	a869831f-0baa-5dcf-acf7-29b5bb7baeaf	INMETRO	Electrolux|H440|004053/2020|220 V	Electrolux	H440	inmetro_refrigerators	\N	709.80	\N	2026-10-15 20:58:22.480867+00	f	220 V	monovolt	220	220	59.15	kWh/mes
b9083cd0-9d22-5a4d-a915-90932c3c1d55	b03224d6-390e-55a5-9ea8-93d8f62bc65c	INMETRO	Samsung|RL4353RBASL/AZ|001495/2017|127 V	Samsung	RL4353RBASL/AZ	inmetro_refrigerators	\N	462.00	\N	2026-10-15 20:58:22.480867+00	f	127 V	monovolt	127	127	38.5	kWh/mes
b980cdbf-63cf-502d-9243-6f170b7fdde0	b03224d6-390e-55a5-9ea8-93d8f62bc65c	INMETRO	Philco|PFG100RP|000963/2021|220 V	Philco	PFG100RP	inmetro_refrigerators	\N	266.40	\N	2026-10-15 20:58:22.480867+00	f	220 V	monovolt	220	220	22.2	kWh/mes
b98a5c19-506b-5a05-af52-c140e527f142	17ec2033-1274-587c-9c08-03f16e660662	INMETRO	EOS|EFB100\nEFB100P|003660/2020|127 V	EOS	EFB100\nEFB100P	inmetro_refrigerators	\N	200.40	\N	2026-10-15 20:58:22.480867+00	f	127 V	monovolt	127	127	16.7	kWh/mes
b99cc220-46d3-51c2-a1bf-312955717291	b03224d6-390e-55a5-9ea8-93d8f62bc65c	INMETRO	BRASTEMP|BRM57|005218/2016|127 V	BRASTEMP	BRM57	inmetro_refrigerators	\N	828.00	\N	2026-10-15 20:58:22.480867+00	f	127 V	monovolt	127	127	69.0	kWh/mes
ba659c9d-4299-5077-9333-069f70a059d4	b03224d6-390e-55a5-9ea8-93d8f62bc65c	INMETRO	Miele|K 2901 Vi 220 Volts|000663/2021|220 V	Miele	K 2901 Vi 220 Volts	inmetro_refrigerators	\N	224.40	\N	2026-10-15 20:58:22.480867+00	f	220 V	monovolt	220	220	18.7	kWh/mes
ba7b8edf-f7ce-5f4d-9e0f-f5b4ff2feb39	b03224d6-390e-55a5-9ea8-93d8f62bc65c	INMETRO	Philco|PRF380I|002671/2020|220 V	Philco	PRF380I	inmetro_refrigerators	\N	432.00	\N	2026-10-15 20:58:22.480867+00	f	220 V	monovolt	220	220	36.0	kWh/mes
baa5f557-085a-5195-a42c-434bbee23d68	b03224d6-390e-55a5-9ea8-93d8f62bc65c	INMETRO	Electrolux|DF35A_DF35X|005404/2016|220 V	Electrolux	DF35A_DF35X	inmetro_refrigerators	\N	468.00	\N	2026-10-15 20:58:22.480867+00	f	220 V	monovolt	220	220	39.0	kWh/mes
bafa94ab-814a-5066-886f-0c9cd7431658	b03224d6-390e-55a5-9ea8-93d8f62bc65c	INMETRO	LG|GS65SDN / GS65SDN1|003968/2017|127 V	LG	GS65SDN / GS65SDN1	inmetro_refrigerators	\N	690.00	\N	2026-10-15 20:58:22.480867+00	f	127 V	monovolt	127	127	57.5	kWh/mes
bbbbeb18-65a5-53a4-9d3d-ccb3837a409f	a869831f-0baa-5dcf-acf7-29b5bb7baeaf	INMETRO	Electrolux|FE22|005399/2016|220 V	Electrolux	FE22	inmetro_refrigerators	\N	511.20	\N	2026-10-15 20:58:22.480867+00	f	220 V	monovolt	220	220	42.6	kWh/mes
bbdf7c00-7fd5-532f-bb47-4e6b8abe6bb3	a869831f-0baa-5dcf-acf7-29b5bb7baeaf	INMETRO	CONSUL|CVU26|005220/2016|220 V	CONSUL	CVU26	inmetro_refrigerators	\N	494.40	\N	2026-10-15 20:58:22.480867+00	f	220 V	monovolt	220	220	41.2	kWh/mes
bca33de7-2d9c-589f-b97a-872fceb7fde4	17ec2033-1274-587c-9c08-03f16e660662	INMETRO	Philco|PFG85B|003271/2019|220 V	Philco	PFG85B	inmetro_refrigerators	\N	145.20	\N	2026-10-15 20:58:22.480867+00	f	220 V	monovolt	220	220	12.1	kWh/mes
be392b58-4e49-559a-9118-f3092e6efc42	b03224d6-390e-55a5-9ea8-93d8f62bc65c	INMETRO	Samsung|RF23R6201SR/BZ|007317/2017|220 V	Samsung	RF23R6201SR/BZ	inmetro_refrigerators	\N	720.00	\N	2026-10-15 20:58:22.480867+00	f	220 V	monovolt	220	220	60.0	kWh/mes
be881505-bc38-570e-b544-e32f228bebc6	b03224d6-390e-55a5-9ea8-93d8f62bc65c	INMETRO	Panasonic|NR-BT42|5576/2017|220 V	Panasonic	NR-BT42	inmetro_refrigerators	\N	372.00	\N	2026-10-15 20:58:22.480867+00	f	220 V	monovolt	220	220	31.0	kWh/mes
bec77c4d-1c65-531a-9e26-6f6c48dc9566	17ec2033-1274-587c-9c08-03f16e660662	INMETRO	EOS|EFB100\nEFB100P|003660/2020|220 V	EOS	EFB100\nEFB100P	inmetro_refrigerators	\N	200.40	\N	2026-10-15 20:58:22.480867+00	f	220 V	monovolt	220	220	16.7	kWh/mes
bf14bbfd-4ef1-53e8-ba12-90d0cb41c60a	b03224d6-390e-55a5-9ea8-93d8f62bc65c	INMETRO	LG|GC-X247CSAV / GC-X247CSA1 / GC-X247CQBV / GC-X247CQB1 / GC-X247CSBV / GC-X247CSB1|003968/2017|127 V	LG	GC-X247CSAV / GC-X247CSA1 / GC-X247CQBV / GC-X247CQB1 / GC-X247CSBV / GC-X247CSB1	inmetro_refrigerators	\N	690.00	\N	2026-10-15 20:58:22.480867+00	f	127 V	monovolt	127	127	57.5	kWh/mes
bf9667aa-743a-58af-a766-57af30c595d7	b03224d6-390e-55a5-9ea8-93d8f62bc65c	INMETRO	Franke|FCB 320 NR ENF V A++ BRA|008199/2019|220 V	Franke	FCB 320 NR ENF V A++ BRA	inmetro_refrigerators	\N	309.60	\N	2026-10-15 20:58:22.480867+00	f	220 V	monovolt	220	220	25.8	kWh/mes
bf9e7340-1a7f-5f5b-ae3e-6607de582664	b03224d6-390e-55a5-9ea8-93d8f62bc65c	INMETRO	Venax|NGV 10|001450/2018|220 V	Venax	NGV 10	inmetro_refrigerators	\N	216.00	\N	2026-10-15 20:58:22.480867+00	f	220 V	monovolt	220	220	18.0	kWh/mes
c03eeaf2-b520-51a4-90aa-5cc3b652f58a	b03224d6-390e-55a5-9ea8-93d8f62bc65c	INMETRO	Electrolux|DC44|005402/2016|127 V	Electrolux	DC44	inmetro_refrigerators	\N	552.00	\N	2026-10-15 20:58:22.480867+00	f	127 V	monovolt	127	127	46.0	kWh/mes
c07dcdf5-cc5b-53a8-88ee-15f6f1935453	a869831f-0baa-5dcf-acf7-29b5bb7baeaf	INMETRO	Philco|PFV300I|005214/2021|220 V	Philco	PFV300I	inmetro_refrigerators	\N	438.00	\N	2026-10-15 20:58:22.480867+00	f	220 V	monovolt	220	220	36.5	kWh/mes
c0a77385-3c8d-5eed-a906-1f03cfda8bec	17ec2033-1274-587c-9c08-03f16e660662	INMETRO	Philco|PFG90RV|001955/2017|220 V	Philco	PFG90RV	inmetro_refrigerators	\N	177.60	\N	2026-10-15 20:58:22.480867+00	f	220 V	monovolt	220	220	14.8	kWh/mes
c0b8e200-b5d0-565f-88c6-9b246dd3421d	b03224d6-390e-55a5-9ea8-93d8f62bc65c	INMETRO	Electrolux|IF56B_IT56S|005404/2016|220 V	Electrolux	IF56B_IT56S	inmetro_refrigerators	\N	436.80	\N	2026-10-15 20:58:22.480867+00	f	220 V	monovolt	220	220	36.4	kWh/mes
c182fb9b-d2a8-519c-8c9e-a9d4d61048e9	b03224d6-390e-55a5-9ea8-93d8f62bc65c	INMETRO	Invita|i-RF-BF-360-XX-2HMA|001451/2018|220 V	Invita	i-RF-BF-360-XX-2HMA	inmetro_refrigerators	\N	454.80	\N	2026-10-15 20:58:22.480867+00	f	220 V	monovolt	220	220	37.9	kWh/mes
c1e8721b-050d-5f12-875e-7b471d8ac5e6	17ec2033-1274-587c-9c08-03f16e660662	INMETRO	Electrolux|RE120|005401/2016|220 V	Electrolux	RE120	inmetro_refrigerators	\N	238.80	\N	2026-10-15 20:58:22.480867+00	f	220 V	monovolt	220	220	19.9	kWh/mes
c23b9b20-21f3-5721-8547-08c9b0434df4	17ec2033-1274-587c-9c08-03f16e660662	INMETRO	Britânia|BFG50B|003271/2019|127 V	Britânia	BFG50B	inmetro_refrigerators	\N	141.60	\N	2026-10-15 20:58:22.480867+00	f	127 V	monovolt	127	127	11.8	kWh/mes
c2cf68cf-510d-57cd-88e1-07b5ca90745c	a869831f-0baa-5dcf-acf7-29b5bb7baeaf	INMETRO	Midea|RCFA32|003109/2016|220 V	Midea	RCFA32	inmetro_refrigerators	\N	386.40	\N	2026-10-15 20:58:22.480867+00	f	220 V	monovolt	220	220	32.2	kWh/mes
c2e82661-23b4-5988-bb9f-108193b296b3	a869831f-0baa-5dcf-acf7-29b5bb7baeaf	INMETRO	Gorenje|FNI5182A1|002508/2019|220 V	Gorenje	FNI5182A1	inmetro_refrigerators	\N	315.60	\N	2026-10-15 20:58:22.480867+00	f	220 V	monovolt	220	220	26.3	kWh/mes
c3225444-58be-5e92-88aa-6963793bf8ba	b03224d6-390e-55a5-9ea8-93d8f62bc65c	INMETRO	Midea|MD-RT507FGA042|002748/2020|220 V	Midea	MD-RT507FGA042	inmetro_refrigerators	\N	553.20	\N	2026-10-15 20:58:22.480867+00	f	220 V	monovolt	220	220	46.1	kWh/mes
c35aec0f-91b7-5d4e-b770-0eccfea3369a	b03224d6-390e-55a5-9ea8-93d8f62bc65c	INMETRO	TECNO|TR30BXDA|004343/2020|127 V	TECNO	TR30BXDA	inmetro_refrigerators	\N	321.60	\N	2026-10-15 20:58:22.480867+00	f	127 V	monovolt	127	127	26.8	kWh/mes
c38a0d4e-051d-5536-9dc8-77ffccdbf7a3	b03224d6-390e-55a5-9ea8-93d8f62bc65c	INMETRO	BRASTEMP|BRM59|005218/2016|127 V	BRASTEMP	BRM59	inmetro_refrigerators	\N	792.00	\N	2026-10-15 20:58:22.480867+00	f	127 V	monovolt	127	127	66.0	kWh/mes
c39c67c3-38b1-5a8a-a0f4-c5f172ddddf3	a869831f-0baa-5dcf-acf7-29b5bb7baeaf	INMETRO	CONSUL|CVU18|005220/2016|127 V	CONSUL	CVU18	inmetro_refrigerators	\N	444.00	\N	2026-10-15 20:58:22.480867+00	f	127 V	monovolt	127	127	37.0	kWh/mes
c44f6eca-7075-5cf9-a5fd-47cff76ac8bb	b03224d6-390e-55a5-9ea8-93d8f62bc65c	INMETRO	Panasonic|NR-BB53|5576/2017|127 V	Panasonic	NR-BB53	inmetro_refrigerators	\N	478.80	\N	2026-10-15 20:58:22.480867+00	f	127 V	monovolt	127	127	39.9	kWh/mes
c4c1ce40-08d4-5039-89d6-4f19a378289b	b03224d6-390e-55a5-9ea8-93d8f62bc65c	INMETRO	Electrolux|DF42_DF42X_TF42_TF42S|005404/2016|127 V	Electrolux	DF42_DF42X_TF42_TF42S	inmetro_refrigerators	\N	636.00	\N	2026-10-15 20:58:22.480867+00	f	127 V	monovolt	127	127	53.0	kWh/mes
c4eec00c-0252-5168-aa23-50cf697b33dc	a869831f-0baa-5dcf-acf7-29b5bb7baeaf	INMETRO	Britânia|BFH109B|003272/2019|220 V	Britânia	BFH109B	inmetro_refrigerators	\N	276.00	\N	2026-10-15 20:58:22.480867+00	f	220 V	monovolt	220	220	23.0	kWh/mes
c4f5e71f-a810-5806-9c1e-c80b90e19ce0	b03224d6-390e-55a5-9ea8-93d8f62bc65c	INMETRO	LG|GR-B413PSJU / GR-B413PSJ1|001421/2019|127 V	LG	GR-B413PSJU / GR-B413PSJ1	inmetro_refrigerators	\N	595.20	\N	2026-10-15 20:58:22.480867+00	f	127 V	monovolt	127	127	49.6	kWh/mes
c5e6116c-82eb-5702-925e-9812c37175cc	17ec2033-1274-587c-9c08-03f16e660662	INMETRO	Midea|MRV10|001496/2017|127 V	Midea	MRV10	inmetro_refrigerators	\N	194.40	\N	2026-10-15 20:58:22.480867+00	f	127 V	monovolt	127	127	16.2	kWh/mes
c66423e3-742c-5cde-be89-e0da55286afe	b03224d6-390e-55a5-9ea8-93d8f62bc65c	INMETRO	CONSUL|CRM55|005218/2016|220 V	CONSUL	CRM55	inmetro_refrigerators	\N	672.00	\N	2026-10-15 20:58:22.480867+00	f	220 V	monovolt	220	220	56.0	kWh/mes
c689a151-6735-54f5-9b9d-1c463fcadba0	a869831f-0baa-5dcf-acf7-29b5bb7baeaf	INMETRO	Crissair|FRZ 06.2 260 Litros 220V|009779/2019|220 V	Crissair	FRZ 06.2 260 Litros 220V	inmetro_refrigerators	\N	384.00	\N	2026-10-15 20:58:22.480867+00	f	220 V	monovolt	220	220	32.0	kWh/mes
c7025086-47e7-54b1-8b66-9d55cc0c10dd	a869831f-0baa-5dcf-acf7-29b5bb7baeaf	INMETRO	Elettromec|FZ-DU-262-XX-2HSB|000069/2018|220 V	Elettromec	FZ-DU-262-XX-2HSB	inmetro_refrigerators	\N	484.80	\N	2026-10-15 20:58:22.480867+00	f	220 V	monovolt	220	220	40.4	kWh/mes
c84368bb-f0de-5191-b30a-315bcf22449c	b03224d6-390e-55a5-9ea8-93d8f62bc65c	INMETRO	BRASTEMP|BRM45|005218/2016|127 V	BRASTEMP	BRM45	inmetro_refrigerators	\N	648.00	\N	2026-10-15 20:58:22.480867+00	f	127 V	monovolt	127	127	54.0	kWh/mes
c8b411d0-570e-58f2-be95-75274da8985e	b03224d6-390e-55a5-9ea8-93d8f62bc65c	INMETRO	Philco|PRF503TI|003507/2020|127 V	Philco	PRF503TI	inmetro_refrigerators	\N	432.00	\N	2026-10-15 20:58:22.480867+00	f	127 V	monovolt	127	127	36.0	kWh/mes
c92d3ef8-70bb-5fba-9f79-b18975524841	b03224d6-390e-55a5-9ea8-93d8f62bc65c	INMETRO	Elettromec|RF-BF-360-VT-2HMB / RF-BF-360-XX-2HMB|001451/2018|220 V	Elettromec	RF-BF-360-VT-2HMB / RF-BF-360-XX-2HMB	inmetro_refrigerators	\N	454.80	\N	2026-10-15 20:58:22.480867+00	f	220 V	monovolt	220	220	37.9	kWh/mes
c934e4f5-183d-560b-b6e9-87acdd31dff9	b03224d6-390e-55a5-9ea8-93d8f62bc65c	INMETRO	BERTAZZONI|REF75PRL|000222/2018|220 V	BERTAZZONI	REF75PRL	inmetro_refrigerators	\N	447.60	\N	2026-10-15 20:58:22.480867+00	f	220 V	monovolt	220	220	37.3	kWh/mes
c939d596-dfb9-556e-8737-8aa955f9518f	b03224d6-390e-55a5-9ea8-93d8f62bc65c	INMETRO	TECNO|TR30BXDA|004343/2020|220 V	TECNO	TR30BXDA	inmetro_refrigerators	\N	321.60	\N	2026-10-15 20:58:22.480867+00	f	220 V	monovolt	220	220	26.8	kWh/mes
c975dead-4bf7-595b-80be-a01ebd323177	a869831f-0baa-5dcf-acf7-29b5bb7baeaf	INMETRO	Philco|PFH440B|003272/2019|220 V	Philco	PFH440B	inmetro_refrigerators	\N	429.60	\N	2026-10-15 20:58:22.480867+00	f	220 V	monovolt	220	220	35.8	kWh/mes
c9fab9df-8749-5876-b2bb-bc342d8fcee8	17ec2033-1274-587c-9c08-03f16e660662	INMETRO	Philco|PH85 Platinum|007591/2016|220 V	Philco	PH85 Platinum	inmetro_refrigerators	\N	210.00	\N	2026-10-15 20:58:22.480867+00	f	220 V	monovolt	220	220	17.5	kWh/mes
cab01d91-e201-59bc-9e39-4de8846ad571	b03224d6-390e-55a5-9ea8-93d8f62bc65c	INMETRO	Samsung|RS65R5691M9/AZ|004878/2019|127 V	Samsung	RS65R5691M9/AZ	inmetro_refrigerators	\N	710.40	\N	2026-10-15 20:58:22.480867+00	f	127 V	monovolt	127	127	59.2	kWh/mes
cad995b9-bad1-50a9-bace-8f2a6d3399cd	17ec2033-1274-587c-9c08-03f16e660662	INMETRO	Galanz|GFb04C01A-Ix220\nGFb04C01A-Pt220\nGFb04C01A-Br220\nGFb04C01A-Ix127\nGFb04C01A-Pt127\nGFb04C01A-Br127|004319/2020|220 V	Galanz	GFb04C01A-Ix220\nGFb04C01A-Pt220\nGFb04C01A-Br220\nGFb04C01A-Ix127\nGFb04C01A-Pt127\nGFb04C01A-Br127	inmetro_refrigerators	\N	153.60	\N	2026-10-15 20:58:22.480867+00	f	220 V	monovolt	220	220	12.8	kWh/mes
cbd760a4-50ee-5e07-920d-b91bd88d76e8	b03224d6-390e-55a5-9ea8-93d8f62bc65c	INMETRO	BRASTEMP|BRS62|005218/2016|220 V	BRASTEMP	BRS62	inmetro_refrigerators	\N	804.00	\N	2026-10-15 20:58:22.480867+00	f	220 V	monovolt	220	220	67.0	kWh/mes
cbed226e-bed0-541b-bf25-0b60d1215cb2	b03224d6-390e-55a5-9ea8-93d8f62bc65c	INMETRO	Continental|TC56_TC56S|005404/2016|220 V	Continental	TC56_TC56S	inmetro_refrigerators	\N	672.00	\N	2026-10-15 20:58:22.480867+00	f	220 V	monovolt	220	220	56.0	kWh/mes
cbfa7efe-6255-5a74-82b9-ef54074de026	b03224d6-390e-55a5-9ea8-93d8f62bc65c	INMETRO	Elettromec|RF-DU-360-XX-2HSB|000070/2018|220 V	Elettromec	RF-DU-360-XX-2HSB	inmetro_refrigerators	\N	216.00	\N	2026-10-15 20:58:22.480867+00	f	220 V	monovolt	220	220	18.0	kWh/mes
ccbe08c9-666f-5c10-8f68-827160fae008	a869831f-0baa-5dcf-acf7-29b5bb7baeaf	INMETRO	Midea|RCFC42|003109/2016|220 V	Midea	RCFC42	inmetro_refrigerators	\N	439.20	\N	2026-10-15 20:58:22.480867+00	f	220 V	monovolt	220	220	36.6	kWh/mes
cce7c328-3072-5768-9be3-5c72a0db6d96	b03224d6-390e-55a5-9ea8-93d8f62bc65c	INMETRO	BRASTEMP|BRM45|005218/2016|220 V	BRASTEMP	BRM45	inmetro_refrigerators	\N	648.00	\N	2026-10-15 20:58:22.480867+00	f	220 V	monovolt	220	220	54.0	kWh/mes
ce5bbf91-b47f-54b9-9fb4-6266cb03d2ad	b03224d6-390e-55a5-9ea8-93d8f62bc65c	INMETRO	Philco|PRF507IP|001056/2020|220 V	Philco	PRF507IP	inmetro_refrigerators	\N	510.00	\N	2026-10-15 20:58:22.480867+00	f	220 V	monovolt	220	220	42.5	kWh/mes
ce7e0713-95c1-52e0-9186-70c1d78b4b93	b03224d6-390e-55a5-9ea8-93d8f62bc65c	INMETRO	BRASTEMP|BRM44|005218/2016|127 V	BRASTEMP	BRM44	inmetro_refrigerators	\N	648.00	\N	2026-10-15 20:58:22.480867+00	f	127 V	monovolt	127	127	54.0	kWh/mes
ceeae780-abb6-5788-afb8-7142f823c93b	a869831f-0baa-5dcf-acf7-29b5bb7baeaf	INMETRO	Electrolux|H550|004053/2020|127 V	Electrolux	H550	inmetro_refrigerators	\N	870.00	\N	2026-10-15 20:58:22.480867+00	f	127 V	monovolt	127	127	72.5	kWh/mes
cf9f0b2f-203a-55c4-90ba-ba446c6d7edb	b03224d6-390e-55a5-9ea8-93d8f62bc65c	INMETRO	Electrolux|IF56B_IT56S|005404/2016|127 V	Electrolux	IF56B_IT56S	inmetro_refrigerators	\N	436.80	\N	2026-10-15 20:58:22.480867+00	f	127 V	monovolt	127	127	36.4	kWh/mes
d2040675-e743-5a94-9b9a-f02584572016	b03224d6-390e-55a5-9ea8-93d8f62bc65c	INMETRO	Samsung|RT46K6A4KS9/FZ|001495/2017|220 V	Samsung	RT46K6A4KS9/FZ	inmetro_refrigerators	\N	499.20	\N	2026-10-15 20:58:22.480867+00	f	220 V	monovolt	220	220	41.6	kWh/mes
d23fb2eb-3c0b-59dd-a3fc-bb4ad9045f77	17ec2033-1274-587c-9c08-03f16e660662	INMETRO	EOS|EFB80\nEFB80P|003660/2020|220 V	EOS	EFB80\nEFB80P	inmetro_refrigerators	\N	170.40	\N	2026-10-15 20:58:22.480867+00	f	220 V	monovolt	220	220	14.2	kWh/mes
d27076c4-225a-5d07-a1bc-680f4d995b91	b03224d6-390e-55a5-9ea8-93d8f62bc65c	INMETRO	TECNO|TR45FXDA|005755/2019|220 V	TECNO	TR45FXDA	inmetro_refrigerators	\N	601.20	\N	2026-10-15 20:58:22.480867+00	f	220 V	monovolt	220	220	50.1	kWh/mes
d29af048-6b7a-58ee-941a-38e36e50888a	b03224d6-390e-55a5-9ea8-93d8f62bc65c	INMETRO	Electrolux|DC35A|005402/2016|220 V	Electrolux	DC35A	inmetro_refrigerators	\N	460.80	\N	2026-10-15 20:58:22.480867+00	f	220 V	monovolt	220	220	38.4	kWh/mes
d34c2ffd-1ac8-5d43-bb29-a6a807f47a1a	b03224d6-390e-55a5-9ea8-93d8f62bc65c	INMETRO	CONSUL|CRM39|005218/2016|127 V	CONSUL	CRM39	inmetro_refrigerators	\N	589.20	\N	2026-10-15 20:58:22.480867+00	f	127 V	monovolt	127	127	49.1	kWh/mes
d4b1a0bd-c3c8-52ac-b184-a0540319a52b	a869831f-0baa-5dcf-acf7-29b5bb7baeaf	INMETRO	CONSUL|CHB53|005219/2016|127 V	CONSUL	CHB53	inmetro_refrigerators	\N	865.20	\N	2026-10-15 20:58:22.480867+00	f	127 V	monovolt	127	127	72.1	kWh/mes
d54f5232-05aa-5714-8988-13f86574a692	17ec2033-1274-587c-9c08-03f16e660662	INMETRO	Britânia|BFG94P|007591/2016|127 V	Britânia	BFG94P	inmetro_refrigerators	\N	216.00	\N	2026-10-15 20:58:22.480867+00	f	127 V	monovolt	127	127	18.0	kWh/mes
d72a8585-a24f-5870-8751-e8f4ea5edf44	b03224d6-390e-55a5-9ea8-93d8f62bc65c	INMETRO	BRASTEMP|BRY59|005218/2016|220 V	BRASTEMP	BRY59	inmetro_refrigerators	\N	756.00	\N	2026-10-15 20:58:22.480867+00	f	220 V	monovolt	220	220	63.0	kWh/mes
d85d448c-4ef2-5f28-b411-0426b023e868	b03224d6-390e-55a5-9ea8-93d8f62bc65c	INMETRO	Continental|TC41_TC41S|005404/2016|220 V	Continental	TC41_TC41S	inmetro_refrigerators	\N	615.60	\N	2026-10-15 20:58:22.480867+00	f	220 V	monovolt	220	220	51.3	kWh/mes
d873f1ba-56f1-598f-a523-9730ac1850ed	b03224d6-390e-55a5-9ea8-93d8f62bc65c	INMETRO	CONSUL|CRM54|005218/2016|220 V	CONSUL	CRM54	inmetro_refrigerators	\N	672.00	\N	2026-10-15 20:58:22.480867+00	f	220 V	monovolt	220	220	56.0	kWh/mes
d8d3d20b-22c8-5a2c-b66e-d0ab554c5630	a869831f-0baa-5dcf-acf7-29b5bb7baeaf	INMETRO	CONSUL|CVU18|005220/2016|220 V	CONSUL	CVU18	inmetro_refrigerators	\N	444.00	\N	2026-10-15 20:58:22.480867+00	f	220 V	monovolt	220	220	37.0	kWh/mes
d98ee1ab-5772-5ce1-87e0-ca3963b39948	b03224d6-390e-55a5-9ea8-93d8f62bc65c	INMETRO	Continental|TC44_TC44S|005404/2016|127 V	Continental	TC44_TC44S	inmetro_refrigerators	\N	663.60	\N	2026-10-15 20:58:22.480867+00	f	127 V	monovolt	127	127	55.3	kWh/mes
d98f7388-84b6-5856-aa21-eb73f7254a6a	b03224d6-390e-55a5-9ea8-93d8f62bc65c	INMETRO	Gorenje|ORB152R|002863/2017|220 V	Gorenje	ORB152R	inmetro_refrigerators	\N	350.40	\N	2026-10-15 20:58:22.480867+00	f	220 V	monovolt	220	220	29.2	kWh/mes
da0ff0ed-a8ed-5e20-96e4-5d8f576e348c	b03224d6-390e-55a5-9ea8-93d8f62bc65c	INMETRO	BRASTEMP|BRE80|005218/2016|127 V	BRASTEMP	BRE80	inmetro_refrigerators	\N	816.00	\N	2026-10-15 20:58:22.480867+00	f	127 V	monovolt	127	127	68.0	kWh/mes
db07911c-b88f-5ad4-b5aa-bf64b0d4de44	17ec2033-1274-587c-9c08-03f16e660662	INMETRO	Philco|PFG51B|001955/2017|127 V	Philco	PFG51B	inmetro_refrigerators	\N	165.60	\N	2026-10-15 20:58:22.480867+00	f	127 V	monovolt	127	127	13.8	kWh/mes
dba76c21-acb1-5c18-b792-85f78308ecc4	b03224d6-390e-55a5-9ea8-93d8f62bc65c	INMETRO	Electrolux|DW44S|005404/2016|220 V	Electrolux	DW44S	inmetro_refrigerators	\N	675.60	\N	2026-10-15 20:58:22.480867+00	f	220 V	monovolt	220	220	56.3	kWh/mes
dbf622fc-5d55-5a57-aeee-d69bb91523f3	b03224d6-390e-55a5-9ea8-93d8f62bc65c	INMETRO	BRASTEMP|BRO81|005218/2016|127 V	BRASTEMP	BRO81	inmetro_refrigerators	\N	872.40	\N	2026-10-15 20:58:22.480867+00	f	127 V	monovolt	127	127	72.7	kWh/mes
dc099b3f-2ace-5e4f-a3d7-305f9a29d72c	b03224d6-390e-55a5-9ea8-93d8f62bc65c	INMETRO	LG|GR-X248LKZM / GR-X248LKZ1|003968/2017|127 V	LG	GR-X248LKZM / GR-X248LKZ1	inmetro_refrigerators	\N	876.00	\N	2026-10-15 20:58:22.480867+00	f	127 V	monovolt	127	127	73.0	kWh/mes
dc76f8ae-7e47-5ca3-a346-005b222febd7	17ec2033-1274-587c-9c08-03f16e660662	INMETRO	EOS|EFB80\nEFB80P|003660/2020|127 V	EOS	EFB80\nEFB80P	inmetro_refrigerators	\N	170.40	\N	2026-10-15 20:58:22.480867+00	f	127 V	monovolt	127	127	14.2	kWh/mes
dcc58c89-c4fe-5c9c-bc38-0bf10e66f4ba	b03224d6-390e-55a5-9ea8-93d8f62bc65c	INMETRO	Samsung|RS50N3413S8/AZ|004878/2019|127 V	Samsung	RS50N3413S8/AZ	inmetro_refrigerators	\N	826.80	\N	2026-10-15 20:58:22.480867+00	f	127 V	monovolt	127	127	68.9	kWh/mes
dd5bc52e-ee5d-50fa-bc2f-132406be916e	b03224d6-390e-55a5-9ea8-93d8f62bc65c	INMETRO	CONSUL|CRD36|005217/2016|127 V	CONSUL	CRD36	inmetro_refrigerators	\N	522.00	\N	2026-10-15 20:58:22.480867+00	f	127 V	monovolt	127	127	43.5	kWh/mes
ddb45a86-2253-5b42-8992-ff0276e2d558	b03224d6-390e-55a5-9ea8-93d8f62bc65c	INMETRO	Electrolux|DC35A|005402/2016|127 V	Electrolux	DC35A	inmetro_refrigerators	\N	460.80	\N	2026-10-15 20:58:22.480867+00	f	127 V	monovolt	127	127	38.4	kWh/mes
de5c8dab-4e9a-5430-bf23-3a59c314c448	b03224d6-390e-55a5-9ea8-93d8f62bc65c	INMETRO	Electrolux|DC44|005402/2016|220 V	Electrolux	DC44	inmetro_refrigerators	\N	552.00	\N	2026-10-15 20:58:22.480867+00	f	220 V	monovolt	220	220	46.0	kWh/mes
dec31cbd-f9d7-5575-99c4-f1f351c864c9	a869831f-0baa-5dcf-acf7-29b5bb7baeaf	INMETRO	Britânia|BFH202B|002580/2017|220 V	Britânia	BFH202B	inmetro_refrigerators	\N	414.00	\N	2026-10-15 20:58:22.480867+00	f	220 V	monovolt	220	220	34.5	kWh/mes
def4013e-364e-599e-9143-331c2c2ba469	a869831f-0baa-5dcf-acf7-29b5bb7baeaf	INMETRO	Philco|PFH105B|003272/2019|127 V	Philco	PFH105B	inmetro_refrigerators	\N	276.00	\N	2026-10-15 20:58:22.480867+00	f	127 V	monovolt	127	127	23.0	kWh/mes
df8ac661-9c9b-5863-a2b0-2273784cc472	b03224d6-390e-55a5-9ea8-93d8f62bc65c	INMETRO	BRASTEMP|BRC12|005222/2016|127 V	BRASTEMP	BRC12	inmetro_refrigerators	\N	228.00	\N	2026-10-15 20:58:22.480867+00	f	127 V	monovolt	127	127	19.0	kWh/mes
dfb386e5-5e2b-535e-812d-fb9b67985ac2	b03224d6-390e-55a5-9ea8-93d8f62bc65c	INMETRO	BERTAZZONI|REF75PIXL|000222/2018|220 V	BERTAZZONI	REF75PIXL	inmetro_refrigerators	\N	447.60	\N	2026-10-15 20:58:22.480867+00	f	220 V	monovolt	220	220	37.3	kWh/mes
dfc9d260-ca47-507a-b135-659ee7683d90	a869831f-0baa-5dcf-acf7-29b5bb7baeaf	INMETRO	BRASTEMP|BVR28|005221/2016|127 V	BRASTEMP	BVR28	inmetro_refrigerators	\N	660.00	\N	2026-10-15 20:58:22.480867+00	f	127 V	monovolt	127	127	55.0	kWh/mes
e003707d-52c2-5eab-a784-8ef840e40b0a	b03224d6-390e-55a5-9ea8-93d8f62bc65c	INMETRO	CONSUL|CRM45|005218/2016|220 V	CONSUL	CRM45	inmetro_refrigerators	\N	630.00	\N	2026-10-15 20:58:22.480867+00	f	220 V	monovolt	220	220	52.5	kWh/mes
e01974f7-7655-5840-9327-3c5fc038c8dd	a869831f-0baa-5dcf-acf7-29b5bb7baeaf	INMETRO	Philco|PFH515B|002580/2017|127 V	Philco	PFH515B	inmetro_refrigerators	\N	801.60	\N	2026-10-15 20:58:22.480867+00	f	127 V	monovolt	127	127	66.8	kWh/mes
e06fe0f4-50ba-5c2a-be82-87a3da89f9d1	b03224d6-390e-55a5-9ea8-93d8f62bc65c	INMETRO	Electrolux|DB52 _DB52X_DT52X_DB53_DB53X|005404/2016|220 V	Electrolux	DB52 _DB52X_DT52X_DB53_DB53X	inmetro_refrigerators	\N	708.00	\N	2026-10-15 20:58:22.480867+00	f	220 V	monovolt	220	220	59.0	kWh/mes
e0bd794f-5beb-5b66-b5af-454de62ad102	b03224d6-390e-55a5-9ea8-93d8f62bc65c	INMETRO	Philco|PRF260RV|003507/2020|220 V	Philco	PRF260RV	inmetro_refrigerators	\N	420.00	\N	2026-10-15 20:58:22.480867+00	f	220 V	monovolt	220	220	35.0	kWh/mes
e14faef7-4724-5d09-b6c7-f46e2ca9ba62	b03224d6-390e-55a5-9ea8-93d8f62bc65c	INMETRO	CONSUL|CRD37|005217/2016|127 V	CONSUL	CRD37	inmetro_refrigerators	\N	522.00	\N	2026-10-15 20:58:22.480867+00	f	127 V	monovolt	127	127	43.5	kWh/mes
e197721d-96cd-59f5-8f55-0e64ba428789	a869831f-0baa-5dcf-acf7-29b5bb7baeaf	INMETRO	Miele|FNS 37402 i|001052/2020|220 V	Miele	FNS 37402 i	inmetro_refrigerators	\N	294.00	\N	2026-10-15 20:58:22.480867+00	f	220 V	monovolt	220	220	24.5	kWh/mes
e28c8639-0f56-530b-9d9b-f3009c9edc35	b03224d6-390e-55a5-9ea8-93d8f62bc65c	INMETRO	Electrolux|DC51_DC51X|005402/2016|127 V	Electrolux	DC51_DC51X	inmetro_refrigerators	\N	705.60	\N	2026-10-15 20:58:22.480867+00	f	127 V	monovolt	127	127	58.8	kWh/mes
e2d81511-23d2-5e7e-a6a4-65b0c0e02317	b03224d6-390e-55a5-9ea8-93d8f62bc65c	INMETRO	Elettromec|RF-MD-472-VT-2HMA / RF-MD-472-XX-2HMA|007381/2020|220 V	Elettromec	RF-MD-472-VT-2HMA / RF-MD-472-XX-2HMA	inmetro_refrigerators	\N	367.20	\N	2026-10-15 20:58:22.480867+00	f	220 V	monovolt	220	220	30.6	kWh/mes
e34a1b4b-674b-5bb2-9fe6-e0e0d5270703	a869831f-0baa-5dcf-acf7-29b5bb7baeaf	INMETRO	BRASTEMP|BVG24|005221/2016|220 V	BRASTEMP	BVG24	inmetro_refrigerators	\N	636.00	\N	2026-10-15 20:58:22.480867+00	f	220 V	monovolt	220	220	53.0	kWh/mes
e390cacf-3508-5a9e-bc7a-e3657b30218f	b03224d6-390e-55a5-9ea8-93d8f62bc65c	INMETRO	Electrolux|IB52_IB52X_IB53_IB53X|005404/2016|220 V	Electrolux	IB52_IB52X_IB53_IB53X	inmetro_refrigerators	\N	548.40	\N	2026-10-15 20:58:22.480867+00	f	220 V	monovolt	220	220	45.7	kWh/mes
e4cff131-10a1-5e10-8526-2f94b8af51e0	b03224d6-390e-55a5-9ea8-93d8f62bc65c	INMETRO	BRASTEMP|BRE57|005218/2016|127 V	BRASTEMP	BRE57	inmetro_refrigerators	\N	792.00	\N	2026-10-15 20:58:22.480867+00	f	127 V	monovolt	127	127	66.0	kWh/mes
e4e4c644-8c2f-5dc7-9a7c-1de42b94530f	b03224d6-390e-55a5-9ea8-93d8f62bc65c	INMETRO	Philco|PRF260RV|003507/2020|127 V	Philco	PRF260RV	inmetro_refrigerators	\N	420.00	\N	2026-10-15 20:58:22.480867+00	f	127 V	monovolt	127	127	35.0	kWh/mes
e6545608-1e44-5ddc-9d71-9df0e4c6568e	b03224d6-390e-55a5-9ea8-93d8f62bc65c	INMETRO	Samsung|RT46K6A4KWW/FZ|001495/2017|127 V	Samsung	RT46K6A4KWW/FZ	inmetro_refrigerators	\N	499.20	\N	2026-10-15 20:58:22.480867+00	f	127 V	monovolt	127	127	41.6	kWh/mes
e747d9fb-8166-5f27-8d2e-6356805b773b	b03224d6-390e-55a5-9ea8-93d8f62bc65c	INMETRO	BERTAZZONI|REF75PIXL|000222/2018|127 V	BERTAZZONI	REF75PIXL	inmetro_refrigerators	\N	447.60	\N	2026-10-15 20:58:22.480867+00	f	127 V	monovolt	127	127	37.3	kWh/mes
e7776f2d-61f4-5ed4-939a-f6cd37486314	b03224d6-390e-55a5-9ea8-93d8f62bc65c	INMETRO	Samsung|RF59A7011SR/AZ|007317/2017|127 V	Samsung	RF59A7011SR/AZ	inmetro_refrigerators	\N	720.00	\N	2026-10-15 20:58:22.480867+00	f	127 V	monovolt	127	127	60.0	kWh/mes
e7e77163-7db2-5737-9db8-3a267879f56b	b03224d6-390e-55a5-9ea8-93d8f62bc65c	INMETRO	CONSUL|CRM43Z|005218/2016|220 V	CONSUL	CRM43Z	inmetro_refrigerators	\N	624.00	\N	2026-10-15 20:58:22.480867+00	f	220 V	monovolt	220	220	52.0	kWh/mes
e83a0a71-59d2-5196-8f79-317fb2659839	b03224d6-390e-55a5-9ea8-93d8f62bc65c	INMETRO	Continental|TC56_TC56S|005404/2016|127 V	Continental	TC56_TC56S	inmetro_refrigerators	\N	672.00	\N	2026-10-15 20:58:22.480867+00	f	127 V	monovolt	127	127	56.0	kWh/mes
e890a23e-689b-5dad-b405-c304ac93370e	b03224d6-390e-55a5-9ea8-93d8f62bc65c	INMETRO	Electrolux|DF56_DF56S_TF56_TF56S|005404/2016|127 V	Electrolux	DF56_DF56S_TF56_TF56S	inmetro_refrigerators	\N	648.00	\N	2026-10-15 20:58:22.480867+00	f	127 V	monovolt	127	127	54.0	kWh/mes
e8a8422c-73a7-518a-8cf2-b352d2896bf1	b03224d6-390e-55a5-9ea8-93d8f62bc65c	INMETRO	BERTAZZONI|REF90X|000222/2018|220 V	BERTAZZONI	REF90X	inmetro_refrigerators	\N	608.40	\N	2026-10-15 20:58:22.480867+00	f	220 V	monovolt	220	220	50.7	kWh/mes
e8b61af9-abfe-54da-ac8e-2e9f1a20a3a9	b03224d6-390e-55a5-9ea8-93d8f62bc65c	INMETRO	Esmaltec|ROC31R|002251/2017|220 V	Esmaltec	ROC31R	inmetro_refrigerators	\N	282.00	\N	2026-10-15 20:58:22.480867+00	f	220 V	monovolt	220	220	23.5	kWh/mes
e8e4f330-712d-5571-b3de-f2cd000179f3	a869831f-0baa-5dcf-acf7-29b5bb7baeaf	INMETRO	Electrolux|H162|005396/2016|220 V	Electrolux	H162	inmetro_refrigerators	\N	319.20	\N	2026-10-15 20:58:22.480867+00	f	220 V	monovolt	220	220	26.6	kWh/mes
e9156156-d3fe-5f7c-915a-7dafc9f34a0f	b03224d6-390e-55a5-9ea8-93d8f62bc65c	INMETRO	Midea|MD-RT507FGA041|002748/2020|127 V	Midea	MD-RT507FGA041	inmetro_refrigerators	\N	628.80	\N	2026-10-15 20:58:22.480867+00	f	127 V	monovolt	127	127	52.4	kWh/mes
e99066c8-8f48-5533-9e4c-b544fe1279d1	b03224d6-390e-55a5-9ea8-93d8f62bc65c	INMETRO	Panasonic|NR-BB71|5576/2017|127 V	Panasonic	NR-BB71	inmetro_refrigerators	\N	490.80	\N	2026-10-15 20:58:22.480867+00	f	127 V	monovolt	127	127	40.9	kWh/mes
ea7cfac3-f9e7-59ff-99b8-541f9d2c9056	b03224d6-390e-55a5-9ea8-93d8f62bc65c	INMETRO	CONSUL|CRM51|005218/2016|220 V	CONSUL	CRM51	inmetro_refrigerators	\N	630.00	\N	2026-10-15 20:58:22.480867+00	f	220 V	monovolt	220	220	52.5	kWh/mes
ec64f107-1ef2-505c-ac3f-1dc4e7767d61	b03224d6-390e-55a5-9ea8-93d8f62bc65c	INMETRO	Philco|PRF520DI|008370/2019|220 V	Philco	PRF520DI	inmetro_refrigerators	\N	735.60	\N	2026-10-15 20:58:22.480867+00	f	220 V	monovolt	220	220	61.3	kWh/mes
edb56719-eaa0-5de5-8813-221c290f3ca6	a869831f-0baa-5dcf-acf7-29b5bb7baeaf	INMETRO	Electrolux|H162|005396/2016|127 V	Electrolux	H162	inmetro_refrigerators	\N	319.20	\N	2026-10-15 20:58:22.480867+00	f	127 V	monovolt	127	127	26.6	kWh/mes
eddfe9f2-b74e-5f04-b976-fe510809c930	b03224d6-390e-55a5-9ea8-93d8f62bc65c	INMETRO	Philco|PFG121RV|000963/2021|127 V	Philco	PFG121RV	inmetro_refrigerators	\N	234.00	\N	2026-10-15 20:58:22.480867+00	f	127 V	monovolt	127	127	19.5	kWh/mes
ef002688-2265-5e97-a804-ad2787f1518c	b03224d6-390e-55a5-9ea8-93d8f62bc65c	INMETRO	Electrolux|DB83_DB83X_DB84_DB84X|005404/2016|127 V	Electrolux	DB83_DB83X_DB84_DB84X	inmetro_refrigerators	\N	816.00	\N	2026-10-15 20:58:22.480867+00	f	127 V	monovolt	127	127	68.0	kWh/mes
efbf4fe6-e473-5f77-a398-c48f026d045a	b03224d6-390e-55a5-9ea8-93d8f62bc65c	INMETRO	Electrolux|DB52 _DB52X_DT52X_DB53_DB53X|005404/2016|127 V	Electrolux	DB52 _DB52X_DT52X_DB53_DB53X	inmetro_refrigerators	\N	708.00	\N	2026-10-15 20:58:22.480867+00	f	127 V	monovolt	127	127	59.0	kWh/mes
efdf5323-f78c-5b9b-be68-c47199a89a98	b03224d6-390e-55a5-9ea8-93d8f62bc65c	INMETRO	Panasonic|NR-BT55|5576/2017|127 V	Panasonic	NR-BT55	inmetro_refrigerators	\N	468.00	\N	2026-10-15 20:58:22.480867+00	f	127 V	monovolt	127	127	39.0	kWh/mes
f04f96c4-6d0e-5f9b-914c-c6f096c1efa6	a869831f-0baa-5dcf-acf7-29b5bb7baeaf	INMETRO	Britânia|BFH202B|002580/2017|127 V	Britânia	BFH202B	inmetro_refrigerators	\N	414.00	\N	2026-10-15 20:58:22.480867+00	f	127 V	monovolt	127	127	34.5	kWh/mes
f066776c-e5d8-5925-8f35-fecd84bf0b64	b03224d6-390e-55a5-9ea8-93d8f62bc65c	INMETRO	LG|GR-X248LKZM / GR-X248LKZ1|003968/2017|220 V	LG	GR-X248LKZM / GR-X248LKZ1	inmetro_refrigerators	\N	876.00	\N	2026-10-15 20:58:22.480867+00	f	220 V	monovolt	220	220	73.0	kWh/mes
f1057a1a-a3ce-5a95-8d00-9f8fdafbb041	b03224d6-390e-55a5-9ea8-93d8f62bc65c	INMETRO	CONSUL|CRC12|005222/2016|127 V	CONSUL	CRC12	inmetro_refrigerators	\N	228.00	\N	2026-10-15 20:58:22.480867+00	f	127 V	monovolt	127	127	19.0	kWh/mes
f27b6eeb-0e47-574a-85f2-4eed0b835cbe	b03224d6-390e-55a5-9ea8-93d8f62bc65c	INMETRO	Electrolux|DF42_DF42X_TF42_TF42S|005404/2016|220 V	Electrolux	DF42_DF42X_TF42_TF42S	inmetro_refrigerators	\N	636.00	\N	2026-10-15 20:58:22.480867+00	f	220 V	monovolt	220	220	53.0	kWh/mes
f2d2b942-a26b-57e2-8cae-3ee5887bce5e	a869831f-0baa-5dcf-acf7-29b5bb7baeaf	INMETRO	CONSUL|CHB42|005219/2016|220 V	CONSUL	CHB42	inmetro_refrigerators	\N	699.60	\N	2026-10-15 20:58:22.480867+00	f	220 V	monovolt	220	220	58.3	kWh/mes
f3424973-8813-5497-ba9f-0b93473c56e0	a869831f-0baa-5dcf-acf7-29b5bb7baeaf	INMETRO	CONSUL|CVU30|005220/2016|127 V	CONSUL	CVU30	inmetro_refrigerators	\N	552.00	\N	2026-10-15 20:58:22.480867+00	f	127 V	monovolt	127	127	46.0	kWh/mes
f34de93e-0fa3-5681-af8a-e88360bfee36	b03224d6-390e-55a5-9ea8-93d8f62bc65c	INMETRO	BRASTEMP|BRM58|005218/2016|127 V	BRASTEMP	BRM58	inmetro_refrigerators	\N	828.00	\N	2026-10-15 20:58:22.480867+00	f	127 V	monovolt	127	127	69.0	kWh/mes
f350718e-8901-5cfe-a91b-d2dce38c1c56	b03224d6-390e-55a5-9ea8-93d8f62bc65c	INMETRO	Samsung|RT38K5A0KWW/FZ|001495/2017|127 V	Samsung	RT38K5A0KWW/FZ	inmetro_refrigerators	\N	471.60	\N	2026-10-15 20:58:22.480867+00	f	127 V	monovolt	127	127	39.3	kWh/mes
f3573ad7-67b6-5281-890c-9e2348d51c7c	17ec2033-1274-587c-9c08-03f16e660662	INMETRO	Philco|PFG90RV|001955/2017|127 V	Philco	PFG90RV	inmetro_refrigerators	\N	163.20	\N	2026-10-15 20:58:22.480867+00	f	127 V	monovolt	127	127	13.6	kWh/mes
f35f3fbe-8739-5dd0-897f-485a93b40900	17ec2033-1274-587c-9c08-03f16e660662	INMETRO	Philco|PFG95B|007591/2016|127 V	Philco	PFG95B	inmetro_refrigerators	\N	216.00	\N	2026-10-15 20:58:22.480867+00	f	127 V	monovolt	127	127	18.0	kWh/mes
f362e217-db3b-5850-a683-425c5b19aae3	a869831f-0baa-5dcf-acf7-29b5bb7baeaf	INMETRO	EOS|EFH250X|003659/2020|127 V	EOS	EFH250X	inmetro_refrigerators	\N	344.40	\N	2026-10-15 20:58:22.480867+00	f	127 V	monovolt	127	127	28.7	kWh/mes
f3893802-d45f-59c6-bc53-69494401c63b	b03224d6-390e-55a5-9ea8-93d8f62bc65c	INMETRO	BRASTEMP|BRE57|005218/2016|220 V	BRASTEMP	BRE57	inmetro_refrigerators	\N	792.00	\N	2026-10-15 20:58:22.480867+00	f	220 V	monovolt	220	220	66.0	kWh/mes
f49e5e3d-371e-558c-a028-15203d778a7f	a869831f-0baa-5dcf-acf7-29b5bb7baeaf	INMETRO	CONSUL|CVU26|005220/2016|127 V	CONSUL	CVU26	inmetro_refrigerators	\N	494.40	\N	2026-10-15 20:58:22.480867+00	f	127 V	monovolt	127	127	41.2	kWh/mes
f4ae4ec3-d883-5fb4-a823-b1de00f281a7	a869831f-0baa-5dcf-acf7-29b5bb7baeaf	INMETRO	Britânia|BFH109B|003272/2019|127 V	Britânia	BFH109B	inmetro_refrigerators	\N	276.00	\N	2026-10-15 20:58:22.480867+00	f	127 V	monovolt	127	127	23.0	kWh/mes
f58aba42-2e57-5adc-9ce5-17db17586a50	b03224d6-390e-55a5-9ea8-93d8f62bc65c	INMETRO	BRASTEMP|BRM56Z|005218/2016|220 V	BRASTEMP	BRM56Z	inmetro_refrigerators	\N	744.00	\N	2026-10-15 20:58:22.480867+00	f	220 V	monovolt	220	220	62.0	kWh/mes
f7954a7b-bd9d-57a3-95e8-8e465f16f1bc	a869831f-0baa-5dcf-acf7-29b5bb7baeaf	INMETRO	CONSUL|CHB53|005219/2016|220 V	CONSUL	CHB53	inmetro_refrigerators	\N	865.20	\N	2026-10-15 20:58:22.480867+00	f	220 V	monovolt	220	220	72.1	kWh/mes
f7f35891-53fd-5d68-bc20-85f5f2128699	b03224d6-390e-55a5-9ea8-93d8f62bc65c	INMETRO	Electrolux|DF56_DF56S_TF56_TF56S|005404/2016|220 V	Electrolux	DF56_DF56S_TF56_TF56S	inmetro_refrigerators	\N	648.00	\N	2026-10-15 20:58:22.480867+00	f	220 V	monovolt	220	220	54.0	kWh/mes
f807f237-5477-5732-a750-d970a2c58786	b03224d6-390e-55a5-9ea8-93d8f62bc65c	INMETRO	CONSUL|CRM42|005218/2016|220 V	CONSUL	CRM42	inmetro_refrigerators	\N	669.60	\N	2026-10-15 20:58:22.480867+00	f	220 V	monovolt	220	220	55.8	kWh/mes
f80a2e63-5896-5d31-89fb-52e28106223d	17ec2033-1274-587c-9c08-03f16e660662	INMETRO	EOS|EFB50\nEFB50P|003660/2020|220 V	EOS	EFB50\nEFB50P	inmetro_refrigerators	\N	189.60	\N	2026-10-15 20:58:22.480867+00	f	220 V	monovolt	220	220	15.8	kWh/mes
f941cfe5-80a9-513e-9d5d-ded79a2ea94a	b03224d6-390e-55a5-9ea8-93d8f62bc65c	INMETRO	Viking Range|VCBB5363 / FDBB5363|007592/2016|127 V	Viking Range	VCBB5363 / FDBB5363	inmetro_refrigerators	\N	734.40	\N	2026-10-15 20:58:22.480867+00	f	127 V	monovolt	127	127	61.2	kWh/mes
f99337f2-a810-5d4c-ab1b-674c3e93e44b	b03224d6-390e-55a5-9ea8-93d8f62bc65c	INMETRO	Electrolux|DM83X_DM84X|005404/2016|220 V	Electrolux	DM83X_DM84X	inmetro_refrigerators	\N	900.00	\N	2026-10-15 20:58:22.480867+00	f	220 V	monovolt	220	220	75.0	kWh/mes
fbc9a7cd-ba28-5cf7-a142-16c1b3ff8ec5	a869831f-0baa-5dcf-acf7-29b5bb7baeaf	INMETRO	Philco|PFZ330B|003272/2019|220 V	Philco	PFZ330B	inmetro_refrigerators	\N	394.80	\N	2026-10-15 20:58:22.480867+00	f	220 V	monovolt	220	220	32.9	kWh/mes
fbe00fbb-6743-5a75-adb4-ba66bfd7cf41	b03224d6-390e-55a5-9ea8-93d8f62bc65c	INMETRO	Electrolux|DF35A_DF35X|005404/2016|127 V	Electrolux	DF35A_DF35X	inmetro_refrigerators	\N	468.00	\N	2026-10-15 20:58:22.480867+00	f	127 V	monovolt	127	127	39.0	kWh/mes
fc172dd7-70cb-5e99-8b19-8edb41b22f77	b03224d6-390e-55a5-9ea8-93d8f62bc65c	INMETRO	Esmaltec|RCD34|002252/2017|127 V	Esmaltec	RCD34	inmetro_refrigerators	\N	462.00	\N	2026-10-15 20:58:22.480867+00	f	127 V	monovolt	127	127	38.5	kWh/mes
fc5210e6-169c-5774-9e45-2f2e3fb240db	b03224d6-390e-55a5-9ea8-93d8f62bc65c	INMETRO	CONSUL|CRC08|005222/2016|220 V	CONSUL	CRC08	inmetro_refrigerators	\N	210.00	\N	2026-10-15 20:58:22.480867+00	f	220 V	monovolt	220	220	17.5	kWh/mes
fc847633-be58-517e-92a3-b794349638bb	a869831f-0baa-5dcf-acf7-29b5bb7baeaf	INMETRO	Electrolux|H440|004053/2020|127 V	Electrolux	H440	inmetro_refrigerators	\N	709.80	\N	2026-10-15 20:58:22.480867+00	f	127 V	monovolt	127	127	59.15	kWh/mes
fd94f1c2-e582-581b-9c30-18a52fce3c43	b03224d6-390e-55a5-9ea8-93d8f62bc65c	INMETRO	Samsung|RF49A5202S9/BZ|001495/2017|220 V	Samsung	RF49A5202S9/BZ	inmetro_refrigerators	\N	522.00	\N	2026-10-15 20:58:22.480867+00	f	220 V	monovolt	220	220	43.5	kWh/mes
fde668b4-a8be-5d07-8c09-271a273be661	b03224d6-390e-55a5-9ea8-93d8f62bc65c	INMETRO	Philco|PRF507IP|001056/2020|127 V	Philco	PRF507IP	inmetro_refrigerators	\N	570.00	\N	2026-10-15 20:58:22.480867+00	f	127 V	monovolt	127	127	47.5	kWh/mes
fdf82dd3-9399-51d7-82d6-c31b161a09b5	b03224d6-390e-55a5-9ea8-93d8f62bc65c	INMETRO	CONSUL|CRM56|005218/2016|127 V	CONSUL	CRM56	inmetro_refrigerators	\N	708.00	\N	2026-10-15 20:58:22.480867+00	f	127 V	monovolt	127	127	59.0	kWh/mes
fea7869b-419b-574c-9aca-212069f66671	a869831f-0baa-5dcf-acf7-29b5bb7baeaf	INMETRO	Miele|F 2811 Vi 127 Volts|001052/2020|127 V	Miele	F 2811 Vi 127 Volts	inmetro_refrigerators	\N	508.80	\N	2026-10-15 20:58:22.480867+00	f	127 V	monovolt	127	127	42.4	kWh/mes
fef357bf-be7a-53d5-b3bb-6d7681a2db48	17ec2033-1274-587c-9c08-03f16e660662	INMETRO	Midea|MRC10B2|001496/2017|220 V	Midea	MRC10B2	inmetro_refrigerators	\N	169.20	\N	2026-10-15 20:58:22.480867+00	f	220 V	monovolt	220	220	14.1	kWh/mes
ff225bdc-b6e7-5477-9ec7-15824436c09d	b03224d6-390e-55a5-9ea8-93d8f62bc65c	INMETRO	Philco|PRF260RP|003507/2020|220 V	Philco	PRF260RP	inmetro_refrigerators	\N	420.00	\N	2026-10-15 20:58:22.480867+00	f	220 V	monovolt	220	220	35.0	kWh/mes
ffbdfb09-f4d2-5286-9ef3-2aa7159844cf	a869831f-0baa-5dcf-acf7-29b5bb7baeaf	INMETRO	CONSUL|CVU20|005220/2016|220 V	CONSUL	CVU20	inmetro_refrigerators	\N	458.40	\N	2026-10-15 20:58:22.480867+00	f	220 V	monovolt	220	220	38.2	kWh/mes
ffe27779-9f01-5973-a996-ca7b0566169a	b03224d6-390e-55a5-9ea8-93d8f62bc65c	INMETRO	BRASTEMP|BRO81|005218/2016|220 V	BRASTEMP	BRO81	inmetro_refrigerators	\N	872.40	\N	2026-10-15 20:58:22.480867+00	f	220 V	monovolt	220	220	72.7	kWh/mes
\.


--
-- Data for Name: registry_user_product; Type: TABLE DATA; Schema: public; Owner: neondb_owner
--

COPY public.registry_user_product (id, avg_active_hours, hours_standby, quantity, product_id, user_id) FROM stdin;
13235ff5-00b1-4a58-b064-9286145e32b4	16.00	8.00	1	026c3fd5-d313-5694-82c0-18f77cc18eb6	1
18025f0d-141b-4a5b-b3fd-b2204d6cd37f	16.00	8.00	1	00507739-daa3-5b3e-b0aa-abcb8d37fabc	1
4c86763b-a26b-4409-a462-f5e018967f84	16.00	8.00	1	040c45bf-e2b7-5682-8fca-1328a4a10a59	1
fb192c19-1e7c-4c96-b146-5eb20f57a291	16.00	10.00	1	022b6365-d7ce-58d0-b3ce-be205f8a0151	1
c715e9e0-45b7-47a0-b30e-c7f6b9aed2e3	20.00	8.00	1	0089f143-81f5-5a62-a72b-d24a769040d8	1
050430f7-0f8e-4197-a184-7d08ac5d69ad	4.00	20.00	1	e4bf7c93-7db0-58b5-972d-f7882fc7b082	1
ad286db5-b056-47e2-a2fe-d8ce12e085eb	4.00	5.00	1	ef7b6029-df37-5b47-820d-33fefd5e5375	1
e43ca553-a3f4-4056-ac91-bbe3cc667582	3.00	0.00	1	b2e17458-91eb-5288-bcfd-1f57bbd66fe9	1
52a98e20-9831-4a21-b2c0-91a60d019774	4.00	22.21	1	f8646dc0-f58c-5b6b-aab3-562c5197382c	3
8fa407ac-26a5-4749-a33c-1afe5a2172e8	4.00	\N	1	ebecd649-8673-5ff5-813c-b93a39d8481e	3
d40a3766-4414-41e1-842d-aed884cf1f33	24.00	15.55	1	0f86c22b-d122-57fe-a3b1-481af0067470	1
30e70e6e-4cd2-4c08-9346-b27b1dc55202	3.00	18.27	2	3c00c3cf-d99d-5541-a36a-32da1ed90050	1
d8119925-3660-462c-a476-f11a03f95b0f	3.00	24.00	2	25b30afa-e987-5c61-a808-021efa553d51	4
ed2ecc32-eafd-4180-b033-6d05525d13d3	5.00	9.90	2	12f975bd-f4d7-5edc-8df1-251d45aacbaa	4
9d7d7bf7-8c5a-4b4b-8b66-a0b79387b62d	316.12	\N	10	05908834-27c8-597f-aea3-a3918717b3d8	1
dad7cc77-3776-4a59-81f4-91cf56b7fbb1	12.00	\N	1	44b15223-7bec-5d67-8fac-db985e3e01c5	5
f31a742e-dd22-4528-bc18-759b1f0e1734	4.00	\N	1	05908834-27c8-597f-aea3-a3918717b3d8	4588452
f1e3ffaf-9ec9-41ac-a074-6748e6d15f07	4.00	\N	1	cd2f57c4-9367-55ec-bebe-0240ed495f0d	4588452
7ce816a3-3edb-4d68-81e9-00f2b1182ab8	4.00	\N	1	f8646dc0-f58c-5b6b-aab3-562c5197382c	4588452
6028752b-0add-4945-9b6a-1687732c3330	4.00	4.00	1	b03224d6-390e-55a5-9ea8-93d8f62bc65c	7465833
fe4b06dd-c153-43de-afba-8ebef3ed2a7d	24.00	0.00	5	37d947f0-88cc-55f1-be5b-d59977d45976	7465833
a8488704-72a0-4b02-a8de-4e4335f6ad60	2.00	0.00	2	3c56d755-1b37-5487-a95a-1882b9a6df57	7465833
7a8977fb-fdd6-430f-a29f-7914ecd9693e	4.00	\N	1	32bc0326-7d0a-5a00-9753-fd6f5f31723e	3214964
\.


--
-- Data for Name: source_metadata; Type: TABLE DATA; Schema: public; Owner: neondb_owner
--

COPY public.source_metadata (id, source, metadata_key, metadata_value) FROM stdin;
\.


--
-- Data for Name: source_product; Type: TABLE DATA; Schema: public; Owner: neondb_owner
--

COPY public.source_product (id, source, source_product_id) FROM stdin;
\.


--
-- Data for Name: users; Type: TABLE DATA; Schema: public; Owner: neondb_owner
--

COPY public.users (id, name) FROM stdin;
1	Usuário Teste
2	test 7366c83e-016e-4234-8d33-600050cfa1e2
3	test 30e948ee-7d9e-49c8-8b3c-e7ea5985296e
4	test a7c9ba5d-724b-4215-896b-e372779084fe
5	test 6f1b981f-48c0-4c44-985a-9dcf1c5fa843
4588452	user 4588452
7465833	user 7465833
3214964	user 3214964
\.


--
-- Name: users_id_seq; Type: SEQUENCE SET; Schema: public; Owner: neondb_owner
--

SELECT pg_catalog.setval('public.users_id_seq', 5, true);


--
-- Name: aggregate_reference aggregate_reference_pkey; Type: CONSTRAINT; Schema: public; Owner: neondb_owner
--

ALTER TABLE ONLY public.aggregate_reference
    ADD CONSTRAINT aggregate_reference_pkey PRIMARY KEY (id);


--
-- Name: aggregate_reference aggregate_reference_source_country_ref_year_metric_applianc_key; Type: CONSTRAINT; Schema: public; Owner: neondb_owner
--

ALTER TABLE ONLY public.aggregate_reference
    ADD CONSTRAINT aggregate_reference_source_country_ref_year_metric_applianc_key UNIQUE (source, country, ref_year, metric, appliance);


--
-- Name: energy_label_class energy_label_class_pkey; Type: CONSTRAINT; Schema: public; Owner: neondb_owner
--

ALTER TABLE ONLY public.energy_label_class
    ADD CONSTRAINT energy_label_class_pkey PRIMARY KEY (id);


--
-- Name: energy_raw_measurement energy_raw_measurement_pkey; Type: CONSTRAINT; Schema: public; Owner: neondb_owner
--

ALTER TABLE ONLY public.energy_raw_measurement
    ADD CONSTRAINT energy_raw_measurement_pkey PRIMARY KEY (id);


--
-- Name: energy_specification energy_specification_pkey; Type: CONSTRAINT; Schema: public; Owner: neondb_owner
--

ALTER TABLE ONLY public.energy_specification
    ADD CONSTRAINT energy_specification_pkey PRIMARY KEY (product_id);


--
-- Name: energy_specification energy_specification_source_source_product_id_key; Type: CONSTRAINT; Schema: public; Owner: neondb_owner
--

ALTER TABLE ONLY public.energy_specification
    ADD CONSTRAINT energy_specification_source_source_product_id_key UNIQUE (source, source_product_id);


--
-- Name: product product_pkey; Type: CONSTRAINT; Schema: public; Owner: neondb_owner
--

ALTER TABLE ONLY public.product
    ADD CONSTRAINT product_pkey PRIMARY KEY (id);


--
-- Name: product_source_observation product_source_observation_pkey; Type: CONSTRAINT; Schema: public; Owner: neondb_owner
--

ALTER TABLE ONLY public.product_source_observation
    ADD CONSTRAINT product_source_observation_pkey PRIMARY KEY (id);


--
-- Name: product_source_observation product_source_observation_source_external_id_key; Type: CONSTRAINT; Schema: public; Owner: neondb_owner
--

ALTER TABLE ONLY public.product_source_observation
    ADD CONSTRAINT product_source_observation_source_external_id_key UNIQUE (source, external_id);


--
-- Name: source_metadata source_metadata_id_source_metadata_key_key; Type: CONSTRAINT; Schema: public; Owner: neondb_owner
--

ALTER TABLE ONLY public.source_metadata
    ADD CONSTRAINT source_metadata_id_source_metadata_key_key UNIQUE (id, source, metadata_key);


--
-- Name: source_metadata source_metadata_pkey; Type: CONSTRAINT; Schema: public; Owner: neondb_owner
--

ALTER TABLE ONLY public.source_metadata
    ADD CONSTRAINT source_metadata_pkey PRIMARY KEY (id);


--
-- Name: source_product source_product_pkey; Type: CONSTRAINT; Schema: public; Owner: neondb_owner
--

ALTER TABLE ONLY public.source_product
    ADD CONSTRAINT source_product_pkey PRIMARY KEY (id);


--
-- Name: source_product source_product_source_source_product_id_key; Type: CONSTRAINT; Schema: public; Owner: neondb_owner
--

ALTER TABLE ONLY public.source_product
    ADD CONSTRAINT source_product_source_source_product_id_key UNIQUE (source, source_product_id);


--
-- Name: registry_user_product userproduct_pkey; Type: CONSTRAINT; Schema: public; Owner: neondb_owner
--

ALTER TABLE ONLY public.registry_user_product
    ADD CONSTRAINT userproduct_pkey PRIMARY KEY (id);


--
-- Name: users users_pkey; Type: CONSTRAINT; Schema: public; Owner: neondb_owner
--

ALTER TABLE ONLY public.users
    ADD CONSTRAINT users_pkey PRIMARY KEY (id);


--
-- Name: idx_product_source_observation_canonical; Type: INDEX; Schema: public; Owner: neondb_owner
--

CREATE INDEX idx_product_source_observation_canonical ON public.product_source_observation USING btree (canonical_product_id);


--
-- Name: idx_product_source_observation_source; Type: INDEX; Schema: public; Owner: neondb_owner
--

CREATE INDEX idx_product_source_observation_source ON public.product_source_observation USING btree (source);


--
-- Name: uk_userproduct_user_product; Type: INDEX; Schema: public; Owner: neondb_owner
--

CREATE UNIQUE INDEX uk_userproduct_user_product ON public.registry_user_product USING btree (user_id, product_id);


--
-- Name: energy_label_class energy_label_class_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: neondb_owner
--

ALTER TABLE ONLY public.energy_label_class
    ADD CONSTRAINT energy_label_class_id_fkey FOREIGN KEY (id) REFERENCES public.product(id) ON DELETE CASCADE;


--
-- Name: energy_raw_measurement energy_raw_measurement_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: neondb_owner
--

ALTER TABLE ONLY public.energy_raw_measurement
    ADD CONSTRAINT energy_raw_measurement_id_fkey FOREIGN KEY (id) REFERENCES public.product(id) ON DELETE CASCADE;


--
-- Name: energy_specification energy_specification_product_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: neondb_owner
--

ALTER TABLE ONLY public.energy_specification
    ADD CONSTRAINT energy_specification_product_id_fkey FOREIGN KEY (product_id) REFERENCES public.product(id) ON DELETE CASCADE;


--
-- Name: registry_user_product fk3etfihtbju2j994iwrlh6wvme; Type: FK CONSTRAINT; Schema: public; Owner: neondb_owner
--

ALTER TABLE ONLY public.registry_user_product
    ADD CONSTRAINT fk3etfihtbju2j994iwrlh6wvme FOREIGN KEY (product_id) REFERENCES public.product(id);


--
-- Name: registry_user_product fkj4ebrocbxucugfqvdt1w2cnim; Type: FK CONSTRAINT; Schema: public; Owner: neondb_owner
--

ALTER TABLE ONLY public.registry_user_product
    ADD CONSTRAINT fkj4ebrocbxucugfqvdt1w2cnim FOREIGN KEY (user_id) REFERENCES public.users(id);


--
-- Name: product_source_observation product_source_observation_canonical_product_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: neondb_owner
--

ALTER TABLE ONLY public.product_source_observation
    ADD CONSTRAINT product_source_observation_canonical_product_id_fkey FOREIGN KEY (canonical_product_id) REFERENCES public.product(id) ON DELETE CASCADE;


--
-- Name: source_metadata source_metadata_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: neondb_owner
--

ALTER TABLE ONLY public.source_metadata
    ADD CONSTRAINT source_metadata_id_fkey FOREIGN KEY (id) REFERENCES public.product(id) ON DELETE CASCADE;


--
-- Name: source_product source_product_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: neondb_owner
--

ALTER TABLE ONLY public.source_product
    ADD CONSTRAINT source_product_id_fkey FOREIGN KEY (id) REFERENCES public.product(id) ON DELETE CASCADE;


--
-- Name: SCHEMA public; Type: ACL; Schema: -; Owner: neondb_owner
--

REVOKE USAGE ON SCHEMA public FROM PUBLIC;


--
-- PostgreSQL database dump complete
--

\unrestrict frqi9Du4ykRdYaDbVskcbmqFmdqT8SScWznclpreAURqI2rQhlf72CbjlA4Bo9F

--
-- Database "postgres" dump
--

\connect postgres

--
-- PostgreSQL database dump
--

\restrict apUbSgZeIxwpq9H92X3eRYc3PDDkIloNSXAucBr4BOl0Hv25DPiqnxZUt89Nv1Y

-- Dumped from database version 18.6 (Debian 18.6-1.pgdg13+2)
-- Dumped by pg_dump version 18.6 (Debian 18.6-1.pgdg13+2)

SET statement_timeout = 0;
SET lock_timeout = 0;
SET idle_in_transaction_session_timeout = 0;
SET transaction_timeout = 0;
SET client_encoding = 'UTF8';
SET standard_conforming_strings = on;
SELECT pg_catalog.set_config('search_path', '', false);
SET check_function_bodies = false;
SET xmloption = content;
SET client_min_messages = warning;
SET row_security = off;

--
-- PostgreSQL database dump complete
--

\unrestrict apUbSgZeIxwpq9H92X3eRYc3PDDkIloNSXAucBr4BOl0Hv25DPiqnxZUt89Nv1Y

--
-- PostgreSQL database cluster dump complete
--
