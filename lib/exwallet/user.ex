defmodule Exwallet.User do
  @moduledoc """
  Implements worker genserver that stores the actual data for a user.

  The state stores users and processed transactions in the following structure:
    %{
      name : <user name>,
      balance: <amount>,
      bets: %{
        <transaction uuid>: nil | <win transaction uuid>
      }
    }
  """
  use GenServer

  @initial_balance_USD 100_000
  @uuid_regex ~r/^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/

  def start_link([usr_reg: ureg, txn_reg: _, name: n] = opts) do
    GenServer.start_link(__MODULE__, opts, name: {:via, Registry, {ureg, n}})
  end

  @impl GenServer
  def init(usr_reg: ureg, txn_reg: treg, name: n) do
    {:ok, %{usr_reg: ureg, txn_reg: treg, name: n, balance: @initial_balance_USD, bets: %{}}}
  end

  @impl GenServer
  def handle_cast({client, {:bet, bet}}, state) do
    with :ok <- check_currency(bet, state),
         :ok <- check_balance(bet, state),
         :ok <- has_valid_bet_uuids(bet, state),
         :ok <- dedup_transaction(bet, state) do
      resp = %{
        user: bet.user,
        status: "RS_OK",
        request_uuid: bet.request_uuid,
        currency: bet.currency,
        balance: state.balance - bet.amount
      }

      finalize_transaction(state.txn_reg, bet.transaction_uuid, resp)
      GenServer.reply(client, resp)

      bets = Map.put(state.bets, bet.transaction_uuid, nil)
      {:noreply, %{state | balance: state.balance - bet.amount, bets: bets}}
    else
      {:reply, resp, _} ->
        GenServer.reply(client, resp)
        {:noreply, state}
    end
  end

  @impl GenServer
  def handle_cast({client, {:win, win}}, state) do
    with :ok <- check_currency(win, state),
         :ok <- check_bet(win, state),
         :ok <- has_valid_win_uuids(win, state),
         :ok <- dedup_transaction(win, state) do
      resp = %{
        user: win.user,
        status: "RS_OK",
        request_uuid: win.request_uuid,
        currency: win.currency,
        balance: state.balance + win.amount
      }

      finalize_transaction(state.txn_reg, win.transaction_uuid, resp)
      GenServer.reply(client, resp)

      bal = state.balance + win.amount
      bets = Map.put(state.bets, win.reference_transaction_uuid, win.transaction_uuid)
      {:noreply, %{state | balance: bal, bets: bets}}
    else
      {:reply, resp, _} ->
        GenServer.reply(client, resp)
        {:noreply, state}
    end
  end

  defp check_currency(%{currency: "USD"}, _state), do: :ok
  defp check_currency(req, state) do
    resp = %{
      user: req.user,
      status: "RS_ERROR_WRONG_CURRENCY",
      request_uuid: req.request_uuid
    }

    {:reply, resp, state}
  end

  defp check_balance(%{amount: amt}, %{balance: bal}) when bal >= amt, do: :ok
  defp check_balance(req, state) do
    resp = %{
      user: req.user,
      status: "RS_ERROR_NOT_ENOUGH_MONEY",
      request_uuid: req.request_uuid
    }

    {:reply, resp, state}
  end

  defp check_bet(%{reference_transaction_uuid: rtuid} = req, %{bets: bets} = state) do
    has_key = Map.has_key?(bets, rtuid)
    cond do
      has_key and is_nil(bets[rtuid]) ->
        :ok

      !has_key ->
        resp = %{
          user: req.user,
          status: "RS_ERROR_TRANSACTION_DOES_NOT_EXIST",
          request_uuid: req.request_uuid
        }
        {:reply, resp, state}

      has_key and !is_nil(bets[rtuid]) and bets[rtuid] != req.transaction_uuid ->
        resp = %{
          user: req.user,
          status: "RS_ERROR_UNKNOWN",
          request_uuid: req.request_uuid
        }
        {:reply, resp, state}

      # this _should_ be unreachable but in case we missed any edge case
      # better to return a generic error than crash; in a production system,
      # we would want to log this and investigate
      true ->
        resp = %{
          user: req.user,
          status: "RS_ERROR_UNKNOWN",
          request_uuid: req.request_uuid
        }
        {:reply, resp, state}
    end
  end

  defp has_valid_bet_uuids(body, state) do
    with :ok <- is_uuid_format(body.transaction_uuid),
         :ok <- is_uuid_format(body.request_uuid) do
      :ok
    else
      _err ->
        resp = %{
          user: body.user,
          status: "RS_ERROR_WRONG_TYPES",
          request_uuid: body.request_uuid
        }

        {:reply, resp, state}
    end
  end

  defp has_valid_win_uuids(body, state) do
    with :ok <- is_uuid_format(body.transaction_uuid),
         :ok <- is_uuid_format(body.reference_transaction_uuid),
         :ok <- is_uuid_format(body.request_uuid) do
      :ok
    else
      _err ->
        resp = %{
          user: body.user,
          status: "RS_ERROR_WRONG_TYPES",
          request_uuid: body.request_uuid
        }

        {:reply, resp, state}
    end
  end

  defp is_uuid_format(uuid) when is_binary(uuid) do
    case Regex.match?(@uuid_regex, uuid) do
      true ->
        :ok
      false ->
        :error
    end
  end
  defp is_uuid_format(_), do: :error

  # deduplicate transactions by "reserving" transaction uuid for new txns
  # and returning the same response for duplicate txns
  defp dedup_transaction(%{transaction_uuid: tid} = req, %{txn_reg: treg} = state) do
    case Registry.register(treg, tid, {req, nil}) do
      {:ok, _} ->
        :ok

      {:error, {:already_registered, _}} ->
        [{_pid, {prev_req, resp}} | _] = Registry.lookup(treg, tid)
        resp =
          if Map.delete(prev_req, :request_uuid) == Map.delete(req, :request_uuid) do
            resp
          else
            %{
              user: req.user,
              status: "RS_ERROR_DUPLICATE_TRANSACTION",
              request_uuid: req.request_uuid
            }
          end
        {:reply, resp, state}
    end
  end

  # update txn record with response for future deduplication
  defp finalize_transaction(txn_registry, tid, resp) do
    Registry.update_value(txn_registry, tid, fn {req, _} -> {req, resp} end)
  end
end
