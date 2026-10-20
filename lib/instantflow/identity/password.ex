defmodule Instantflow.Identity.Password do
  @moduledoc "PBKDF2-HMAC-SHA256 passwords with random salts and constant-time verification."
  @iterations 600_000
  def hash(password) do
    salt = :crypto.strong_rand_bytes(16)
    digest = :crypto.pbkdf2_hmac(:sha256, password, salt, @iterations, 32)
    Enum.join([@iterations, Base.encode64(salt), Base.encode64(digest)], ":")
  end

  def valid?(password, encoded) when is_binary(password) and byte_size(password) <= 512 do
    [iterations, salt, expected] = String.split(encoded, ":")

    digest =
      :crypto.pbkdf2_hmac(
        :sha256,
        password,
        Base.decode64!(salt),
        String.to_integer(iterations),
        32
      )

    Plug.Crypto.secure_compare(digest, Base.decode64!(expected))
  end

  def valid?(_, _), do: false

  def dummy_verify do
    :crypto.pbkdf2_hmac(:sha256, "invalid", <<0::128>>, @iterations, 32)
    false
  end
end
