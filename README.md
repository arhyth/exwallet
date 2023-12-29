# ExWallet

An in-memory debit/credit wallet application. This does not include transaction semantics between user wallets.

This coding exercise was a partial requirement in a job application to test engineering skills in Elixir. This should help show acumen in interpreting and implementing specification and mitigating if not eliminating undefined behavior.

## Requirements
1. Satisfy the following API
```elixir
@doc """
Start a linked and isolated supervision tree and return the root server that
will handle the requests.
"""
@spec start :: GenServer.server()

@doc """
Create non-existing users with currency as "USD" and amount as 100_000.

It must ignore empty binary `""` or if the user already exists.
"""
@spec create_users(server :: GenServer.server(), users :: [String.t()]) :: :ok

@doc """
The same behavior is from `POST /transaction/debit` docs.

The `body` parameter is the "body" from the docs as a map with keys as atoms.
The result is the "response" from the docs as a map with keys as atoms.
"""
@spec debit(server :: GenServer.server(), body :: map) :: map

@doc """
The same behavior is from `POST /transaction/credit` docs.

The `body` parameter is the "body" from the docs as a map with keys as atoms.
The result is the "response" from the docs as a map with keys as atoms.
"""
@spec credit(server :: GenServer.server(), body :: map) :: map
```
2. Debit and credit operations must be idempotent; there is a `transaction_uuid` included in every request to help with this
3. Duplicate requests (all same parameters) must return same response as original
4. Duplicate requests (different param but reuse transaction_uuid) must return an error
5. Debit requests that have larger amount than current balance must return an error
6. Debit and credit requests must be made against same currency, in this exercise only `USD`
7. In cases of failed requests for (5)-(7), the client is free to reuse `transaction_uuid` and the implementation must be able to handle such scenario
8. Must be performant and handle 80% correctness and load testing done by the submission review

## Architecture

![architecture](exwallet-architecture.svg)

### Start up (white broken lines)
- `ExWallet.Root` starts `ExWallet.Transaction.Registry`, `ExWallet.User.Registry` and `ExWallet.Partitioner` under a Supervisor.

### User creation (blue lines)
- For every user, `ExWallet.Root` finds the appropriate DynamicSupervisor via `ExWallet.Partitioner` and issues request to create a `ExWallet.User` under it with a name registered to `ExWallet.User.Registry`.

### Duplicate Debit or Credit transaction (green lines)
- `ExWallet.Root` checks `ExWallet.Transaction.Registry` if a previous transaction with the same *transaction_uuid* has already been processed and if found, returns the recorded response synchronously.

### New Debit or Credit transaction (red lines)
- Otherwise, the `ExWallet.Root` issues an asynchronous message to `ExWallet.User`, with `ExWallet.User` replying directly to the client (not pictured here) once it's processed the transaction.