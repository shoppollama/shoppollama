defmodule Shoppollama.Repo do
  use Ecto.Repo,
    otp_app: :shoppollama,
    adapter: Ecto.Adapters.SQLite3
end
