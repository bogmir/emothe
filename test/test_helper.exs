# `:slow` tests are excluded by default; run them with `mix test --include slow`.
# Tagged: test/playcode/export/tei_validator_test.exs (xmllint against the TEI
# RelaxNG schema, ~15s per test).
ExUnit.start(exclude: [:slow])
Ecto.Adapters.SQL.Sandbox.mode(Playcode.Repo, :manual)
