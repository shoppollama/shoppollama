defmodule Shoppollama.Store do
  use Ecto.Schema
  import Ecto.Changeset

  schema "stores" do
    field :shop_domain, :string
    field :access_token, :string
    field :shop_name, :string
    field :is_active, :boolean, default: true

    timestamps()
  end

  @doc false
  def changeset(store, attrs) do
    store
    |> cast(attrs, [:shop_domain, :access_token, :shop_name, :is_active])
    |> validate_required([:shop_domain, :access_token])
    |> unique_constraint(:shop_domain)
    |> validate_format(:shop_domain, ~r/^[a-zA-Z0-9\-]+\.myshopify\.com$/)
  end
end
