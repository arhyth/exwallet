defmodule Exwallet.Root do
  @moduledoc """
  Implements root genserver, routing logic for user creation to partitioned
  dynamic supervisors, and API calls to worker genservers
  """
  use GenServer

  @impl GenServer
  def init(_opts) do
    # This randomization is necessary to account for multiple instances
    # of this server running in the same node, eg. in tests.
    dt = DateTime.to_unix(DateTime.utc_now(), :millisecond)
    rnd = for _ <- 1..4, into: "", do: <<Enum.random(~c"0123456789abcdefghijklmnopqrstuvwxyz")>>
    ureg_name = :"Exwallet.User.Registry.#{dt}.#{rnd}"
    treg_name = :"Exwallet.Transaction.Registry.#{dt}.#{rnd}"
    part_name = :"Exwallet.Partitioner.#{dt}.#{rnd}"

    children = [
      {Registry, keys: :unique, partitions: System.schedulers_online(), name: ureg_name},
      {Registry, keys: :unique, partitions: System.schedulers_online(), name: treg_name},
      {PartitionSupervisor, child_spec: DynamicSupervisor, name: part_name}
    ]

    {:ok, _} = Supervisor.start_link(children, strategy: :one_for_one)

    {:ok, %{usr_reg: ureg_name, txn_reg: treg_name, partitioner: part_name}}
  end

  @impl GenServer
  def handle_call(
        {:create_users, users},
        _from,
        %{usr_reg: ureg, txn_reg: treg, partitioner: part} = state
      ) do
    for_retry =
      users
      |> Enum.filter(fn u ->
        Enum.empty?(Registry.lookup(ureg, u))
      end)
      |> Enum.reduce([], fn u, for_retry ->
        started =
          DynamicSupervisor.start_child(
            {:via, PartitionSupervisor, {part, u}},
            {Exwallet.User, [usr_reg: ureg, txn_reg: treg, name: u]}
          )

        case started do
          {:ok, _} ->
            for_retry

          {:error, :already_started} ->
            for_retry

          {:error, _} ->
            [u | for_retry]
        end
      end)

    # retry request after 300-600ms, if that still fails just drop it :shrug:
    Process.send_after(self(), {:create_users, for_retry}, 10 * Enum.random(30..60))

    {:reply, :ok, state}
  end

  @impl GenServer
  def handle_call({req_type, body} = msg, from, state) when req_type in [:bet, :win] do
    with :ok <- is_valid_amount(body, state),
         {:ok, pid} <- lookup_user(body, state) do
      GenServer.cast(pid, {from, msg})
      {:noreply, state}
    end
  end

  @impl GenServer
  def handle_info(
        {:create_users, users},
        %{usr_reg: ureg, txn_reg: treg, partitioner: part} = state
      ) do
    users
    |> Enum.filter(fn u ->
      Enum.empty?(Registry.lookup(ureg, u))
    end)
    |> Enum.each(fn u ->
      DynamicSupervisor.start_child(
        {:via, PartitionSupervisor, {part, u}},
        {Exwallet.User, [usr_reg: ureg, txn_reg: treg, name: u]}
      )
    end)

    {:noreply, state}
  end

  defp lookup_user(%{user: ""} = body, state) do
    resp = %{
      user: "",
      status: "RS_ERROR_UNKNOWN",
      request_uuid: body.request_uuid
    }

    {:reply, resp, state}
  end

  defp lookup_user(%{user: u} = body, %{usr_reg: reg} = state) do
    case Registry.lookup(reg, u) do
      [{pid, _}] ->
        {:ok, pid}

      _notfound ->
        resp = %{
          user: u,
          status: "RS_ERROR_UNKNOWN",
          request_uuid: body.request_uuid
        }

        {:reply, resp, state}
    end
  end

  defp is_valid_amount(%{amount: amount}, _state)
       when is_number(amount) and amount > 0,
       do: :ok

  defp is_valid_amount(%{amount: amount} = body, state)
       when is_number(amount) and amount <= 0 do
    resp = %{
      user: body.user,
      status: "RS_ERROR_UNKNOWN",
      request_uuid: body.request_uuid
    }

    {:reply, resp, state}
  end

  defp is_valid_amount(%{amount: amt} = body, state) when not is_number(amt) do
    resp = %{
      user: body.user,
      status: "RS_ERROR_WRONG_TYPES",
      request_uuid: body.request_uuid
    }

    {:reply, resp, state}
  end
end
