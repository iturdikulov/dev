#!/usr/bin/env python3

import asyncio
import struct
import os
from typing import Tuple

# Фиксированная часть ключа (можно менять)
BASE_KEY = 0x55
# Соль (генерируется случайно при старте сервера)
SALT = os.urandom(16)  # 16 байт случайной соли

def generate_key(salt: bytes, base_key: int) -> bytes:
    """Генерирует ключ на основе соли и базового значения."""
    return bytes([(base_key + salt[i % len(salt)]) % 256 for i in range(256)])

# Генерируем ключ один раз при старте
XOR_KEY = generate_key(SALT, BASE_KEY)

def xor_encrypt(data: bytes, key: bytes) -> bytes:
    """XOR-шифрование с динамическим ключом."""
    return bytes([data[i] ^ key[i % len(key)] for i in range(len(data))])

def xor_decrypt(data: bytes, key: bytes) -> bytes:
    """XOR-дешифрование (совпадает с шифрованием)."""
    return xor_encrypt(data, key)

class SOCKS5Proxy:
    async def handle_client(self, reader: asyncio.StreamReader, writer: asyncio.StreamWriter):
        # 1. Приветствие (SOCKS5 handshake)
        greeting = await reader.read(2)
        if greeting != b"\x05\x01":
            writer.close()
            return

        writer.write(b"\x05\x00")  # Без аутентификации
        await writer.drain()

        # 2. Запрос подключения
        request = await reader.read(4)
        if request[0] != 0x05 or request[1] != 0x01:
            writer.close()
            return

        # Определяем тип адреса
        addr_type = request[3]
        if addr_type == 0x01:  # IPv4
            addr = await reader.read(4)
            addr = ".".join(str(b) for b in addr)
        elif addr_type == 0x03:  # Domain
            domain_len = await reader.read(1)
            addr = await reader.read(domain_len[0])
            addr = addr.decode()
        else:
            writer.close()
            return

        port = await reader.read(2)
        port = struct.unpack(">H", port)[0]

        # 3. Подключение к целевому серверу
        try:
            remote_reader, remote_writer = await asyncio.open_connection(addr, port)
        except Exception:
            writer.write(b"\x05\x01\x00\x01\x00\x00\x00\x00\x00\x00")  # Ошибка
            await writer.drain()
            writer.close()
            return

        # 4. Ответ клиенту об успешном подключении
        writer.write(b"\x05\x00\x00\x01\x00\x00\x00\x00\x00\x00")
        await writer.drain()

        # 5. Проксирование трафика с шифрованием
        async def proxy(src: asyncio.StreamReader, dst: asyncio.StreamWriter, encrypt: bool):
            while True:
                try:
                    data = await src.read(4096)
                    if not data:
                        break
                    processed = xor_encrypt(data, XOR_KEY) if encrypt else xor_decrypt(data, XOR_KEY)
                    dst.write(processed)
                    await dst.drain()
                except Exception:
                    break
            dst.close()

        await asyncio.gather(
            proxy(reader, remote_writer, encrypt=True),
            proxy(remote_reader, writer, encrypt=False),
        )

async def main():
    print(f"Соль: {SALT.hex()}")
    print(f"Ключ: {XOR_KEY.hex()}")
    server = await asyncio.start_server(SOCKS5Proxy().handle_client, "127.0.0.1", 8082)
    print("SOCKS5 прокси запущен на 0.0.0.0:8082 (с солью)")
    async with server:
        await server.serve_forever()

if __name__ == "__main__":
    asyncio.run(main())

