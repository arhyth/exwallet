defmodule Exwallet do
  @moduledoc """
  A betting wallet module using only in-memory data and standard library.
  Includes implementation for the root genserver that handles routing of request to worker genservers.
  """

  @doc """
  Start a linked and isolated supervision tree and return the root server that
  will handle the requests.
  """
  @spec start :: GenServer.server()
  def start do
    {:ok, pid} = GenServer.start(Exwallet.Root, [])
    pid
  end

  @doc """
  Create non-existing users with currency as "USD" and amount as 100_000.

  It must ignore empty binary `""` or if the user already exists.
  """
  @spec create_users(server :: GenServer.server(), users :: [String.t()]) :: :ok
  def create_users(server, users) do
    users = Enum.filter(users, fn u -> u != "" end)
    GenServer.call(server, {:create_users, users})
    :ok
  end

  @doc """
  The same behavior is from `POST /transaction/bet` docs.

  The `body` parameter is the "body" from the docs as a map with keys as atoms.
  The result is the "response" from the docs as a map with keys as atoms.
  """
  @spec bet(server :: GenServer.server(), body :: map) :: map
  def bet(server, body) do
    GenServer.call(server, {:bet, body})
  end

  @doc """
  The same behavior is from `POST /transaction/win` docs.

  The `body` parameter is the "body" from the docs as a map with keys as atoms.
  The result is the "response" from the docs as a map with keys as atoms.
  """
  @spec win(server :: GenServer.server(), body :: map) :: map
  def win(server, body) do
    GenServer.call(server, {:win, body})
  end
end
