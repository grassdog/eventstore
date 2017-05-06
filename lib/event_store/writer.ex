defmodule EventStore.Writer do
  @moduledoc """
  Single process writer to assign a monotonically increasing id and persist events to the store
  """

  use GenServer
  require Logger

  Postgrex.Types.define(EventStore.PostgrexTypes, [Postgrex.Extensions.JSONB], json: Poison)

  alias EventStore.{Subscriptions,RecordedEvent,Writer}
  alias EventStore.Storage.{Appender,QueryLatestEventId}

  defstruct conn: nil, next_event_id: 1

  def start_link do
    GenServer.start_link(__MODULE__, %Writer{}, name: __MODULE__)
  end

  def init(%Writer{} = state) do
    storage_config =
      Application.get_env(:eventstore, EventStore.Storage)
      |> EventStore.Config.parse()
      |> Keyword.merge(types: EventStore.PostgrexTypes)

    {:ok, conn} = Postgrex.start_link(storage_config)

    GenServer.cast(self(), {:latest_event_id})

    {:ok, %Writer{state | conn: conn}}
  end

  @doc """
  Append the given list of events to the stream
  """
  def append_to_stream(events, stream_id, stream_uuid)
  def append_to_stream([], _stream_id, _stream_uuid), do: :ok
  def append_to_stream(events, stream_id, stream_uuid) do
    GenServer.call(__MODULE__, {:append_to_stream, events, stream_id, stream_uuid})
  end

  def handle_call({:append_to_stream, events, stream_id, stream_uuid}, _from, %Writer{conn: conn, next_event_id: next_event_id} = state) do
    recorded_events = assign_event_id(events, next_event_id)

    {reply, state} = case append_events(conn, stream_id, recorded_events) do
      {:ok, count} ->
        publish_events(stream_uuid, recorded_events)
        {:ok, %Writer{state | next_event_id: next_event_id + count}}
      {:error, _reason} = reply -> {reply, state}
    end

    {:reply, reply, state}
  end

  def handle_cast({:latest_event_id}, %Writer{conn: conn} = state) do
    {:ok, last_event_id} = QueryLatestEventId.execute(conn)

    {:noreply, %Writer{state | next_event_id: last_event_id + 1}}
  end

  defp assign_event_id(events, next_event_id) do
    events
    |> Enum.with_index(0)
    |> Enum.map(fn {recorded_event, index} ->
      %RecordedEvent{recorded_event |
        event_id: next_event_id + index
      }
    end)
  end

  defp append_events(conn, stream_id, recorded_events) do
    Appender.append(conn, stream_id, recorded_events)
  end

  defp publish_events(stream_uuid, recorded_events) do
    Subscriptions.notify_events(stream_uuid, recorded_events)
  end
end
