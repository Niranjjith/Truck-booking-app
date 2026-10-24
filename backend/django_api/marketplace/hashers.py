import bcrypt
from django.contrib.auth.hashers import BasePasswordHasher, mask_hash


class LegacyBcryptPasswordHasher(BasePasswordHasher):
    algorithm = "bcrypt"

    def salt(self):
        return bcrypt.gensalt(rounds=12).decode("ascii")

    def encode(self, password, salt):
        password_bytes = password.encode("utf-8")
        if len(password_bytes) > 72:
            raise ValueError("Bcrypt passwords may not exceed 72 UTF-8 bytes")
        hashed = bcrypt.hashpw(password_bytes, salt.encode("ascii")).decode("ascii")
        return f"{self.algorithm}${hashed}"

    def verify(self, password, encoded):
        _, hashed = encoded.split("$", 1)
        password_bytes = password.encode("utf-8")
        if len(password_bytes) > 72:
            return False
        try:
            return bcrypt.checkpw(password_bytes, hashed.encode("ascii"))
        except ValueError:
            return False

    def decode(self, encoded):
        algorithm, hashed = encoded.split("$", 1)
        return {"algorithm": algorithm, "hash": hashed, "salt": ""}

    def safe_summary(self, encoded):
        decoded = self.decode(encoded)
        return {
            "algorithm": decoded["algorithm"],
            "hash": mask_hash(decoded["hash"]),
        }

    def must_update(self, encoded):
        return False

    def harden_runtime(self, password, encoded):
        return None
