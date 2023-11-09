defmodule ExGoogleSTT.StreamingServer.DynamicSupervisor do
  use DynamicSupervisor

  alias ExGoogleSTT.StreamingServer

  def start_link(init_arg) do
    DynamicSupervisor.start_link(__MODULE__, init_arg, name: __MODULE__)
  end

  @impl true
  def init(_init_arg) do
    create_ets_table()
    DynamicSupervisor.init(strategy: :one_for_one)
  end

  def create_ets_table() do
    :ets.new(:stt_client_registry, [
      :set,
      :public,
      :named_table,
      {:read_concurrency, true},
      {:write_concurrency, true}
    ])
  end

  def get_or_start_stream(caller_pid, configs) do
    case get(caller_pid) do
      nil ->
        start_child(caller_pid, configs)

      streamer_pid ->
        streamer_pid
    end
  end

  def start_child(caller_pid, configs) do
    DynamicSupervisor.start_child(__MODULE__, {ExGoogleSTT.StreamingServer, caller_pid, configs})
  end

  defp get(caller_pid) do
    case :ets.lookup(:stt_client_registry, caller_pid) do
      [] ->
        nil

      [{_key, streamer_pid}] ->
        streamer_pid
    end
  end

  defp put(caller_pid, streamer_pid) do
    :ets.insert(:stt_client_registry, {caller_pid, streamer_pid})
  end
end
