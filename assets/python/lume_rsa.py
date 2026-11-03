"""PyCryptodome RSA API backed by the bundled cryptography runtime.

Keep imports lazy so loading unrelated Spiders does not initialize OpenSSL.
"""
import sys
import types


class RsaKey:
    def __init__(self, key):
        self._key = key

    def has_private(self):
        from cryptography.hazmat.primitives.asymmetric import rsa
        return isinstance(self._key, rsa.RSAPrivateKey)

    def public_key(self):
        return RsaKey(self._key.public_key()) if self.has_private() else self

    publickey = public_key

    @property
    def n(self):
        return self.public_key()._key.public_numbers().n

    @property
    def e(self):
        return self.public_key()._key.public_numbers().e

    @property
    def d(self):
        return self._key.private_numbers().d

    def size_in_bits(self):
        return self._key.key_size

    def size_in_bytes(self):
        return (self.size_in_bits() + 7) // 8

    def export_key(self, format="PEM", passphrase=None, pkcs=1, **kwargs):
        from cryptography.hazmat.primitives import serialization as s
        if kwargs:
            raise ValueError("RSA export_key 不支持的参数：" + ", ".join(kwargs))
        encoding = {"PEM": s.Encoding.PEM, "DER": s.Encoding.DER}.get(format)
        if encoding is None:
            raise ValueError("RSA export_key 支持 PEM / DER")
        if self.has_private():
            secret = passphrase.encode() if isinstance(passphrase, str) else passphrase
            return self._key.private_bytes(
                encoding,
                s.PrivateFormat.PKCS8 if pkcs == 8 else s.PrivateFormat.TraditionalOpenSSL,
                s.BestAvailableEncryption(secret) if secret else s.NoEncryption(),
            )
        return self._key.public_bytes(encoding, s.PublicFormat.SubjectPublicKeyInfo)

    exportKey = export_key


def import_key(extern_key, passphrase=None):
    from cryptography.hazmat.primitives import serialization as s
    from cryptography.hazmat.primitives.asymmetric import rsa
    data = extern_key.encode() if isinstance(extern_key, str) else bytes(extern_key)
    password = passphrase.encode() if isinstance(passphrase, str) else passphrase
    for loader in (s.load_pem_private_key, s.load_der_private_key):
        try:
            key = loader(data, password=password)
            if isinstance(key, rsa.RSAPrivateKey):
                return RsaKey(key)
        except (ValueError, TypeError):
            pass
    for loader in (s.load_pem_public_key, s.load_der_public_key, s.load_ssh_public_key):
        try:
            key = loader(data)
            if isinstance(key, rsa.RSAPublicKey):
                return RsaKey(key)
        except (ValueError, TypeError):
            pass
    raise ValueError("RSA 密钥格式无效或口令不正确")


def construct(components, consistency_check=True):
    from cryptography.hazmat.primitives.asymmetric import rsa
    values = tuple(int(value) for value in components)
    if len(values) == 2:
        return RsaKey(rsa.RSAPublicNumbers(values[1], values[0]).public_key())
    if len(values) not in (3, 5, 6):
        raise ValueError("RSA.construct 需要 n, e[, d[, p, q[, u]]]")
    n, e, d = values[:3]
    p, q = values[3:5] if len(values) >= 5 else rsa.rsa_recover_prime_factors(n, e, d)
    return RsaKey(rsa.RSAPrivateNumbers(
        p, q, d, rsa.rsa_crt_dmp1(d, p), rsa.rsa_crt_dmq1(d, q),
        rsa.rsa_crt_iqmp(p, q), rsa.RSAPublicNumbers(e, n),
    ).private_key())


def generate(bits, randfunc=None, e=65537):
    from cryptography.hazmat.primitives.asymmetric import rsa
    if randfunc is not None:
        raise ValueError("RSA.generate 当前不支持自定义随机函数")
    return RsaKey(rsa.generate_private_key(public_exponent=e, key_size=bits))


def _hash(module=None):
    from cryptography.hazmat.primitives import hashes
    name = getattr(module, "_name", getattr(module, "name", "sha1"))
    return {"md5": hashes.MD5, "sha1": hashes.SHA1, "sha224": hashes.SHA224,
            "sha256": hashes.SHA256, "sha384": hashes.SHA384, "sha512": hashes.SHA512}[name]()


class _Cipher:
    def __init__(self, key, padding, sentinel=False):
        self.key, self.padding, self.sentinel = key, padding, sentinel

    def encrypt(self, message):
        return self.key.public_key()._key.encrypt(bytes(message), self.padding)

    def decrypt(self, ciphertext, sentinel=None, expected_pt_len=0):
        if not self.key.has_private():
            raise TypeError("RSA 解密需要私钥")
        try:
            value = self.key._key.decrypt(bytes(ciphertext), self.padding)
            if expected_pt_len and len(value) != expected_pt_len:
                raise ValueError("RSA 明文长度不匹配")
            return value
        except ValueError:
            if self.sentinel:
                return sentinel
            raise


def _oaep(key, hashAlgo=None, mgfunc=None, label=b"", randfunc=None):
    from cryptography.hazmat.primitives.asymmetric import padding
    if mgfunc is not None or randfunc is not None:
        raise ValueError("RSA OAEP 当前不支持自定义 MGF 或随机函数")
    digest = _hash(hashAlgo)
    return _Cipher(key, padding.OAEP(mgf=padding.MGF1(digest), algorithm=digest, label=label))


def _v15(key, randfunc=None):
    from cryptography.hazmat.primitives.asymmetric import padding
    if randfunc is not None:
        raise ValueError("RSA PKCS1 当前不支持自定义随机函数")
    return _Cipher(key, padding.PKCS1v15(), sentinel=True)


class _Signature:
    def __init__(self, key):
        self.key = key

    def sign(self, digest):
        from cryptography.hazmat.primitives.asymmetric import padding, utils
        return self.key._key.sign(digest.digest(), padding.PKCS1v15(), utils.Prehashed(_hash(digest)))

    def verify(self, digest, signature):
        from cryptography.exceptions import InvalidSignature
        from cryptography.hazmat.primitives.asymmetric import padding, utils
        try:
            self.key.public_key()._key.verify(bytes(signature), digest.digest(), padding.PKCS1v15(), utils.Prehashed(_hash(digest)))
        except InvalidSignature as error:
            raise ValueError("RSA 签名无效") from error


def install(crypto, cipher):
    public = types.ModuleType("Crypto.PublicKey")
    public.__path__ = []
    rsa = types.ModuleType("Crypto.PublicKey.RSA")
    rsa.import_key = rsa.importKey = import_key
    rsa.construct, rsa.RsaKey = construct, RsaKey
    rsa.generate = generate
    public.RSA, crypto.PublicKey = rsa, public
    signature = types.ModuleType("Crypto.Signature")
    signature.__path__ = []
    pkcs = types.ModuleType("Crypto.Signature.pkcs1_15")
    pkcs.new = _Signature
    signature.pkcs1_15, crypto.Signature = pkcs, signature
    for name, factory in (("PKCS1_v1_5", _v15), ("PKCS1_OAEP", _oaep)):
        module = types.ModuleType("Crypto.Cipher." + name)
        module.new = factory
        setattr(cipher, name, module)
        sys.modules[module.__name__] = module
    for module in (public, rsa, signature, pkcs):
        sys.modules[module.__name__] = module
