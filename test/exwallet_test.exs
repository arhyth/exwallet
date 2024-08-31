defmodule ExwalletTest do
  use ExUnit.Case
  doctest Exwallet

  describe "start/0" do
    test "returns pid on success" do
      result = Exwallet.start()
      assert is_pid(result)
    end
  end

  describe "create_users/2" do
    setup do
      srv = Exwallet.start()
      on_exit(fn -> Process.exit(srv, :kill) end)
      %{server: srv}
    end

    test "creates users", %{server: srv} do
      assert Exwallet.create_users(srv, ["user1", "user2"]) == :ok
    end

    test "ignores empty user", %{server: srv} do
      assert Exwallet.create_users(srv, [""]) == :ok
      bet = %{
        user: "",
        transaction_uuid: "16d2dcfe-b89e-11e7-854a-58404eea6d16",
        request_uuid: "583c985f-fee6-4c0e-bbf5-308aad6265af",
        currency: "USD",
        bet: "zero",
        amount: 10500
      }

      result = Exwallet.bet(srv, bet)
      assert Map.get(result, :status) == "RS_ERROR_UNKNOWN"
    end
  end

  describe "bet/2" do
    setup do
      srv = Exwallet.start()
      on_exit(fn -> Process.exit(srv, :kill) end)
      %{srv: srv}
    end

    test "debits bets from users", %{srv: srv} do
      assert Exwallet.create_users(srv, ["user1"]) == :ok
      bet = %{
        user: "user1",
        currency: "USD",
        transaction_uuid: "16d2dcfe-b89e-11e7-854a-58404eea6d16",
        request_uuid: "583c985f-fee6-4c0e-bbf5-308aad6265af",
        amount: 10_000,
      }
      result = Exwallet.bet(srv, bet)
      assert result.balance == 90_000
    end

    test "returns error on non-UUID format identifiers", %{srv: srv} do
      assert Exwallet.create_users(srv, ["user1"]) == :ok
      bet = %{
        user: "user1",
        currency: "USD",
        transaction_uuid: "16d2dcfe-b89e-11e7-invalid",
        request_uuid: "583c985f-fee6-4c0e-bbf5-wrong",
        amount: 10_000,
      }
      result = Exwallet.bet(srv, bet)
      assert result.status == "RS_ERROR_WRONG_TYPES"
    end

    test "returns error on insufficient balance", %{srv: srv} do
      assert Exwallet.create_users(srv, ["user2"]) == :ok
      bet = %{
        user: "user2",
        currency: "USD",
        transaction_uuid: "16d2dcfe-b89e-11e7-854a-58404eea6d16",
        request_uuid: "583c985f-fee6-4c0e-bbf5-308aad6265af",
        amount: 102_300,
      }
      result = Exwallet.bet(srv, bet)
      assert result.status == "RS_ERROR_NOT_ENOUGH_MONEY"
    end

    test "returns error on negative amount", %{srv: srv} do
      assert Exwallet.create_users(srv, ["user1"]) == :ok
      bet = %{
        user: "user1",
        currency: "USD",
        transaction_uuid: "16d2dcfe-b89e-11e7-854a-58404eea6d16",
        request_uuid: "583c985f-fee6-4c0e-bbf5-308aad6265af",
        amount: -10_000,
      }
      result = Exwallet.bet(srv, bet)
      assert result.status == "RS_ERROR_UNKNOWN"
    end

    test "returns error on nonexistent user", %{srv: srv} do
      bet = %{
        user: "nonexistent1",
        request_uuid: "583c985f-fee6-4c0e-bbf5-308aad6265af",
        currency: "USD",
        amount: 10_000,
      }
      result = Exwallet.bet(srv, bet)
      assert result.status == "RS_ERROR_UNKNOWN"
    end

    test "returns same OK response on duplicate transaction with same data", %{srv: srv} do
      assert Exwallet.create_users(srv, ["duper1"]) == :ok
      bet = %{
        user: "duper1",
        currency: "USD",
        transaction_uuid: "16d2dcfe-b89e-11e7-854a-58404eea6d16",
        request_uuid: "583c985f-fee6-4c0e-bbf5-308aad6265af",
        amount: 10_000,
      }
      orig_result = Exwallet.bet(srv, bet)
      assert orig_result.status == "RS_OK"
      assert orig_result.balance == 90_000
      bet = %{
        user: "duper1",
        currency: "USD",
        transaction_uuid: "16d2dcfe-b89e-11e7-854a-58404eea6d16",
        request_uuid: "583c985f-fee6-4c0e-bbf5-45e4bf1d24fb",
        amount: 10_000,
      }
      dup_result = Exwallet.bet(srv, bet)
      assert dup_result == orig_result
    end

    test "returns error on duplicate transaction with different data", %{srv: srv} do
      assert Exwallet.create_users(srv, ["duper2"]) == :ok
      bet = %{
        user: "duper2",
        currency: "USD",
        transaction_uuid: "16d2dcfe-b89e-11e7-854a-58404eea6d16",
        request_uuid: "583c985f-fee6-4c0e-bbf5-308aad6265af",
        amount: 10_000,
      }
      result = Exwallet.bet(srv, bet)
      assert result.balance == 90_000
      bet = %{
        user: "duper2",
        currency: "USD",
        transaction_uuid: "16d2dcfe-b89e-11e7-854a-58404eea6d16",
        request_uuid: "583c985f-fee6-4c0e-bbf5-308aad6265af",
        amount: 15_000,
      }
      dup_result = Exwallet.bet(srv, bet)
      assert dup_result.status == "RS_ERROR_DUPLICATE_TRANSACTION"
    end
  end

  describe "win/2" do
    setup do
      srv = Exwallet.start()
      on_exit(fn -> Process.exit(srv, :kill) end)
      %{srv: srv}
    end

    test "credits win for user bet", %{srv: srv} do
      assert Exwallet.create_users(srv, ["winner1"]) == :ok
      bet = %{
        user: "winner1",
        currency: "USD",
        transaction_uuid: "16d2dcfe-b89e-11e7-854a-58404eea6d16",
        request_uuid: "583c985f-fee6-4c0e-bbf5-308aad6265af",
        amount: 10_000,
      }
      result = Exwallet.bet(srv, bet)
      assert result.balance == 90_000
      win = %{
        user: "winner1",
        currency: "USD",
        reference_transaction_uuid: "16d2dcfe-b89e-11e7-854a-58404eea6d16",
        transaction_uuid: "39c207bb-e421-6c3b-a9f3-caf04be29815",
        request_uuid: "583c985f-fee6-4c0e-bbf5-308aad6265af",
        amount: 15_000,
      }
      result = Exwallet.win(srv, win)
      assert result.balance == 105_000
    end

    test "returns error on non-number amount", %{srv: srv} do
      assert Exwallet.create_users(srv, ["user1"]) == :ok
      win = %{
        user: "user1",
        currency: "USD",
        reference_transaction_uuid: "16d2dcfe-b89e-11e7-854a-58404eea6d16",
        transaction_uuid: "16d2dcfe-b89e-11e7-854a-58404eea6d16",
        request_uuid: "583c985f-fee6-4c0e-bbf5-308aad6265af",
        amount: "NaN",
      }
      result = Exwallet.win(srv, win)
      assert result.status == "RS_ERROR_WRONG_TYPES"
    end

    test "returns error on negative amount", %{srv: srv} do
      assert Exwallet.create_users(srv, ["user1"]) == :ok
      win = %{
        user: "user1",
        currency: "USD",
        reference_transaction_uuid: "16d2dcfe-b89e-11e7-854a-58404eea6d16",
        request_uuid: "583c985f-fee6-4c0e-bbf5-308aad6265af",
        transaction_uuid: "29d2dcfe-b89e-11e7-854a-58404eea6b37",
        amount: -10_000,
      }
      result = Exwallet.win(srv, win)
      assert result.status == "RS_ERROR_UNKNOWN"
    end

    test "returns error on bet with an existing win", %{srv: srv} do
      assert Exwallet.create_users(srv, ["winner2"]) == :ok
      bet = %{
        user: "winner2",
        currency: "USD",
        transaction_uuid: "29d2dcfe-b89e-11e7-854a-58404eea6cf7",
        request_uuid: "583c985f-fee6-4c0e-bbf5-308aad6265af",
        amount: 10_000,
      }
      result = Exwallet.bet(srv, bet)
      assert result.balance == 90_000
      win = %{
        user: "winner2",
        currency: "USD",
        reference_transaction_uuid: "29d2dcfe-b89e-11e7-854a-58404eea6cf7",
        transaction_uuid: "d58207bb-a421-654b-d963-7ac04b462b37",
        request_uuid: "583c985f-fee6-4c0e-bbf5-308aad6265af",
        amount: 15_000,
      }
      result = Exwallet.win(srv, win)
      assert result.balance == 105_000
      notwin = %{
        user: "winner2",
        currency: "USD",
        reference_transaction_uuid: "29d2dcfe-b89e-11e7-854a-58404eea6cf7",
        transaction_uuid: "a5dfe923-6421-6prb-8f34-74efb91b2ab5",
        request_uuid: "583c985f-fee6-4c0e-bbf5-0g8b73y0tb3b",
        amount: 15_000,
      }
      result = Exwallet.win(srv, notwin)
      assert result.status == "RS_ERROR_UNKNOWN"
    end
  end
end
