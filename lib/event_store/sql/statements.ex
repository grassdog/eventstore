defmodule EventStore.Sql.Statements do
  @moduledoc """
  PostgreSQL statements to intialize the event store schema and read/write streams and events.
  """

  def initializers do
    [
      create_streams_table(),
      create_stream_uuid_index(),
      create_events_table(),
      create_event_stream_id_index(),
      create_event_stream_id_and_version_index(),
      create_subscriptions_table(),
      create_subscription_index(),
      create_snapshots_table(),
    ]
  end

  def truncate_tables do
"""
TRUNCATE TABLE snapshots, subscriptions, streams, events
RESTART IDENTITY;
"""
  end

  defp create_streams_table do
"""
CREATE TABLE streams
(
    stream_id bigserial PRIMARY KEY NOT NULL,
    stream_uuid text NOT NULL,
    created_at timestamp without time zone default (now() at time zone 'utc') NOT NULL
);
"""
  end

  defp create_stream_uuid_index do
"""
CREATE UNIQUE INDEX ix_streams_stream_uuid ON streams (stream_uuid);
"""
  end

  defp create_events_table do
"""
CREATE TABLE events
(
    event_id bigint PRIMARY KEY NOT NULL,
    stream_id bigint NOT NULL REFERENCES streams (stream_id),
    stream_version bigint NOT NULL,
    event_type text NOT NULL,
    correlation_id text,
    causation_id text,
    data jsonb NOT NULL,
    metadata jsonb NULL,
    created_at timestamp without time zone default (now() at time zone 'utc') NOT NULL
);
"""
  end

  defp create_event_stream_id_index do
"""
CREATE INDEX ix_events_stream_id ON events (stream_id);
"""
  end

  defp create_event_stream_id_and_version_index do
"""
CREATE UNIQUE INDEX ix_events_stream_id_stream_version ON events (stream_id, stream_version DESC);
"""
  end

  defp create_subscriptions_table do
"""
CREATE TABLE subscriptions
(
    subscription_id bigserial PRIMARY KEY NOT NULL,
    stream_uuid text NOT NULL,
    subscription_name text NOT NULL,
    last_seen_event_id bigint NULL,
    last_seen_stream_version bigint NULL,
    created_at timestamp without time zone default (now() at time zone 'utc') NOT NULL
);
"""
  end

  def create_subscription_index do
"""
CREATE UNIQUE INDEX ix_subscriptions_stream_uuid_subscription_name ON subscriptions (stream_uuid, subscription_name);
"""
  end

  def create_snapshots_table do
"""
CREATE TABLE snapshots
(
    source_uuid text PRIMARY KEY NOT NULL,
    source_version bigint NOT NULL,
    source_type text NOT NULL,
    data jsonb NOT NULL,
    metadata jsonb NULL,
    created_at timestamp without time zone default (now() at time zone 'utc') NOT NULL
);
"""
  end

  def create_stream do
"""
INSERT INTO streams (stream_uuid)
VALUES ($1)
RETURNING stream_id;
"""
  end

  def create_events(number_of_events \\ 1) do
    insert = ["INSERT INTO events (event_id, stream_id, stream_version, correlation_id, causation_id, event_type, data, metadata, created_at) VALUES"]

    params =
      1..number_of_events
      |> Enum.map(fn event_number ->
        index = (event_number - 1) * 9
        event_params = [
          "($",
          Integer.to_string(index + 1), ", $",
          Integer.to_string(index + 2), ", $",
          Integer.to_string(index + 3), ", $",
          Integer.to_string(index + 4), ", $",
          Integer.to_string(index + 5), ", $",
          Integer.to_string(index + 6), ", $",
          Integer.to_string(index + 7), ", $",
          Integer.to_string(index + 8), ", $",
          Integer.to_string(index + 9), ")"
        ]

        if event_number == number_of_events do
          event_params
        else
          [event_params, ","]
        end
      end)

    [insert, " ", params, ";"]
  end

  def create_subscription do
"""
INSERT INTO subscriptions (stream_uuid, subscription_name, last_seen_event_id, last_seen_stream_version)
VALUES ($1, $2, $3, $4)
RETURNING subscription_id, stream_uuid, subscription_name, last_seen_event_id, last_seen_stream_version, created_at;
"""
  end

  def delete_subscription do
"""
DELETE FROM subscriptions
WHERE stream_uuid = $1 AND subscription_name = $2;
"""
  end

  def ack_last_seen_event do
"""
UPDATE subscriptions
SET last_seen_event_id = $3, last_seen_stream_version = $4
WHERE stream_uuid = $1 AND subscription_name = $2;
"""
  end

  def record_snapshot do
"""
INSERT INTO snapshots (source_uuid, source_version, source_type, data, metadata)
VALUES ($1, $2, $3, $4, $5)
ON CONFLICT (source_uuid)
DO UPDATE SET source_version = $2, source_type = $3, data = $4, metadata = $5;
"""
  end

  def delete_snapshot do
"""
DELETE FROM snapshots
WHERE source_uuid = $1;
"""
  end

  def query_all_subscriptions do
"""
SELECT subscription_id, stream_uuid, subscription_name, last_seen_event_id, last_seen_stream_version, created_at
FROM subscriptions
ORDER BY created_at;
"""
  end

  def query_get_subscription do
"""
SELECT subscription_id, stream_uuid, subscription_name, last_seen_event_id, last_seen_stream_version, created_at
FROM subscriptions
WHERE stream_uuid = $1 AND subscription_name = $2;
"""
  end

  def query_stream_id do
"""
SELECT stream_id
FROM streams
WHERE stream_uuid = $1;
"""
  end

  def query_stream_id_and_latest_version do
"""
SELECT s.stream_id,
  (SELECT COALESCE(e.stream_version, 0)
   FROM events e
   WHERE e.stream_id = s.stream_id
   ORDER BY e.stream_version DESC
   LIMIT 1) stream_version
FROM streams s
WHERE s.stream_uuid = $1;
"""
  end

  def query_latest_version do
"""
SELECT stream_version
FROM events
WHERE stream_id = $1
ORDER BY stream_version DESC
LIMIT 1;
"""
  end

  def query_latest_event_id do
"""
SELECT COALESCE(MAX(event_id), 0)
FROM events;
"""
  end

  def query_get_snapshot do
"""
SELECT source_uuid, source_version, source_type, data, metadata, created_at
FROM snapshots
WHERE source_uuid = $1;
"""
  end

  def read_events_forward do
"""
SELECT
  event_id,
  stream_id,
  stream_version,
  event_type,
  correlation_id,
  causation_id,
  data,
  metadata,
  created_at
FROM events
WHERE stream_id = $1 and stream_version >= $2
ORDER BY stream_version ASC
LIMIT $3;
"""
  end

  def read_all_events_forward do
"""
SELECT
  event_id,
  stream_id,
  stream_version,
  event_type,
  correlation_id,
  causation_id,
  data,
  metadata,
  created_at
FROM events
WHERE event_id >= $1
ORDER BY event_id ASC
LIMIT $2;
"""
  end
end
