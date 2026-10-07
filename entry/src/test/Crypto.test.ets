import { describe, it, expect } from '@ohos/hypium';
import { Coding } from '../main/ets/crypto/Coding';
import { Key, KeyFormatException, KeyFormatType } from '../main/ets/crypto/Key';
import { Blake2s } from '../main/ets/crypto/Blake2s';
import { Hkdf } from '../main/ets/crypto/Hkdf';

// ===== 测试辅助 =====

function ascii(s: string): Uint8Array {
  const out = new Uint8Array(s.length);
  for (let i = 0; i < s.length; i++) {
    out[i] = s.charCodeAt(i) & 0xFF;
  }
  return out;
}

function range(n: number): Uint8Array {
  const out = new Uint8Array(n);
  for (let i = 0; i < n; i++) {
    out[i] = i & 0xFF;
  }
  return out;
}

function hex(s: string): Uint8Array {
  return Coding.hexDecode(s);
}

function expectBytes(actual: Uint8Array, expectedHex: string): void {
  expect(Coding.hexEncode(actual)).assertEqual(expectedHex);
}

/** 确定性 rng：i & 0xFF 递增序列。 */
function deterministicRng(len: number): Uint8Array {
  return range(len);
}

export default function cryptoTest() {
  describe('Crypto', () => {

    // ---------- base64 / hex ----------

    it('base64: 编解码往返（长度 mod 3 = 0/1/2）', 0, () => {
      expect(Coding.base64Encode(new Uint8Array(0))).assertEqual('');
      expect(Coding.base64Encode(ascii('f'))).assertEqual('Zg==');
      expect(Coding.base64Encode(ascii('fo'))).assertEqual('Zm8=');
      expect(Coding.base64Encode(ascii('foo'))).assertEqual('Zm9v');
      expect(Coding.base64Encode(ascii('foob'))).assertEqual('Zm9vYg==');
      expect(Coding.base64Encode(ascii('foobar'))).assertEqual('Zm9vYmFy');
      expectBytes(Coding.base64Decode('Zm9vYmFy'), Coding.hexEncode(ascii('foobar')));
      // 32 字节密钥形态往返（43 数据字符 + 1 padding）
      const keyBytes = range(32);
      const b64 = Coding.base64Encode(keyBytes);
      expect(b64.length).assertEqual(44);
      expect(b64.charAt(43)).assertEqual('=');
      expectBytes(Coding.base64Decode(b64), Coding.hexEncode(keyBytes));
    });

    it('base64: 严格校验（非法字符/非法 padding/非 4 倍数）', 0, () => {
      const bad: string[] = ['Zg=', 'Zg===', 'Z g=', 'Z-==', 'Zm9v!bFy', '=g==', 'Zg=a', 'AAA'];
      for (let i = 0; i < bad.length; i++) {
        let threw = false;
        try {
          Coding.base64Decode(bad[i]);
        } catch (e) {
          threw = true;
        }
        expect(threw).assertTrue();
      }
      // 合法边界不应抛错
      expectBytes(Coding.base64Decode('AAAA'), '000000');
      expectBytes(Coding.base64Decode('////'), 'ffffff');
    });

    it('hex: 编解码往返与错误路径', 0, () => {
      expect(Coding.hexEncode(hex('00ff10ab'))).assertEqual('00ff10ab');
      expect(Coding.hexEncode(hex('ABCD'))).assertEqual('abcd'); // 大写输入可解、输出小写
      let threw = false;
      try {
        Coding.hexDecode('abc');
      } catch (e) {
        threw = true;
      }
      expect(threw).assertTrue();
      threw = false;
      try {
        Coding.hexDecode('zz');
      } catch (e) {
        threw = true;
      }
      expect(threw).assertTrue();
    });

    // ---------- Key ----------

    it('Key: fromBase64 正常解析与往返', 0, () => {
      const b64 = Coding.base64Encode(range(32));
      const key = Key.fromBase64(b64);
      expect(key.toBase64()).assertEqual(b64);
      expectBytes(key.toBytes(), Coding.hexEncode(range(32)));
    });

    it('Key: 长度错误（43/45 字符）与解码后非 32 字节', 0, () => {
      const cases: string[] = [
        Coding.base64Encode(range(32)).substring(0, 43), // 43 字符
        Coding.base64Encode(range(32)) + 'A',            // 45 字符
        'AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA=='  // 44 字符但解码 31 字节
      ];
      for (let i = 0; i < cases.length; i++) {
        let caught: Error | null = null;
        try {
          Key.fromBase64(cases[i]);
        } catch (e) {
          caught = e as Error;
        }
        expect(caught instanceof KeyFormatException).assertTrue();
        expect((caught as KeyFormatException).formatType).assertEqual(KeyFormatType.LENGTH);
        expect((caught as KeyFormatException).message).assertEqual('密钥长度错误');
      }
    });

    it('Key: 非法字符', 0, () => {
      const base = Coding.base64Encode(range(32));
      const bad = base.substring(0, 10) + '!' + base.substring(11);
      let caught: Error | null = null;
      try {
        Key.fromBase64(bad);
      } catch (e) {
        caught = e as Error;
      }
      expect(caught instanceof KeyFormatException).assertTrue();
      expect((caught as KeyFormatException).formatType).assertEqual(KeyFormatType.CONTENTS);
      expect((caught as KeyFormatException).message).assertEqual('密钥中含错误字符');
    });

    it('Key: generate 注入 rng / 防御性拷贝 / equals', 0, () => {
      const key = Key.generate(deterministicRng);
      expectBytes(key.toBytes(), Coding.hexEncode(range(32)));
      // 默认构造防御性拷贝：外部数组改动不影响内部
      const src = range(32);
      const k2 = new Key(src);
      src[0] = 0xEE;
      expect(k2.toBytes()[0]).assertEqual(0);
      // toBytes 返回副本
      const out = k2.toBytes();
      out[0] = 0xDD;
      expect(k2.toBytes()[0]).assertEqual(0);
      expect(k2.equals(new Key(range(32)))).assertTrue();
      expect(k2.equals(key)).assertTrue();
      expect(k2.equals(new Key(new Uint8Array(32)))).assertFalse();
    });

    it('Key: 构造长度非 32 直接抛 LENGTH', 0, () => {
      let caught: Error | null = null;
      try {
        new Key(new Uint8Array(31));
      } catch (e) {
        caught = e as Error;
      }
      expect(caught instanceof KeyFormatException).assertTrue();
    });

    // ---------- BLAKE2s KAT（python3 hashlib.blake2s 生成，RFC 7693 等价） ----------

    it('Blake2s: 无密钥 KAT（空/abc/跨块长消息/短输出）', 0, () => {
      expectBytes(Blake2s.hash(new Uint8Array(0)),
        '69217a3079908094e11121d042354a7c1f55b6482ca1a51e1b250dfd1ed0eef9');
      expectBytes(Blake2s.hash(ascii('abc')),
        '508c5e8c327c14e2e1a72ba34eeb452f37458b209ed63a294d999b4c86675982');
      // 360 字节，跨越多个 64 字节块
      let longData = new Uint8Array(0);
      const seg = ascii('The quick brown fox jumps over the lazy dog. ');
      longData = new Uint8Array(seg.length * 8);
      for (let i = 0; i < 8; i++) {
        longData.set(seg, i * seg.length);
      }
      expect(longData.length).assertEqual(360);
      expectBytes(Blake2s.hash(longData),
        '4b175cfa2e6c9ba2615034b3577a1d6d6dc5a51bbdddd7df2192e9caf979ba1d');
      // 可变输出长度
      expectBytes(Blake2s.hash(ascii('wireguard'), 16), 'f63395e6393f7d8e4ea545c2aed61596');
      expectBytes(Blake2s.hash(ascii('wireguard'), 20), 'f6383d4023c661e29d7fc2ca7535037bc9eb3902');
      // 64 字节边界（整块即最终块）
      const exact64 = range(64);
      expectBytes(Blake2s.hash(exact64), Coding.hexEncode(Blake2s.hash(exact64, 32)));
    });

    it('Blake2s: keyed KAT（含空消息/长消息/短输出/短密钥）', 0, () => {
      const key = range(32);
      expectBytes(Blake2s.keyedHash(key, new Uint8Array(0)),
        '48a8997da407876b3d79c0d92325ad3b89cbb754d86ab71aee047ad345fd2c49');
      expectBytes(Blake2s.keyedHash(key, ascii('abc')),
        'a281f725754969a702f6fe36fc591b7def866e4b70173ece402fc01c064d6b65');
      const long = new Uint8Array(512);
      const seg = range(256);
      long.set(seg, 0);
      long.set(seg, 256);
      // 该向量使用独立密钥 'WireGuard-HarmonyOS-key-material'（32 字节 ASCII）
      expectBytes(Blake2s.keyedHash(ascii('WireGuard-HarmonyOS-key-material'), long),
        '0d274394bc9624e1bb5b58c5c9cfdcacf1ee95517cb9054927719e5286984b52');
      expectBytes(Blake2s.keyedHash(key, ascii('mac input'), 16), 'cd15b4715680ff8852bf47f5e1381753');
      expectBytes(Blake2s.keyedHash(ascii('k'), ascii('data')),
        '856ac87e73834f0fcbf5e3a1efdc428de3bd73fb5444414600e15f279cac95bf');
    });

    it('Blake2s: WireGuard 初始链式哈希常量', 0, () => {
      // blake2s("WireGuard v1 zx2c4 Jason@zx2c4.com") —— 握手协议 FIXED_CK
      expectBytes(Blake2s.hash(ascii('WireGuard v1 zx2c4 Jason@zx2c4.com')),
        '8622b0d3e9ecfbba175eaa380b1c67eb8db9ecb01b2199c52d99952b27c8d03d');
    });

    it('Blake2s: 参数非法抛错', 0, () => {
      let threw = false;
      try {
        Blake2s.hash(new Uint8Array(0), 33);
      } catch (e) {
        threw = true;
      }
      expect(threw).assertTrue();
      threw = false;
      try {
        Blake2s.keyedHash(new Uint8Array(33), new Uint8Array(0));
      } catch (e) {
        threw = true;
      }
      expect(threw).assertTrue();
    });

    // ---------- HKDF（RFC 5869，HMAC-BLAKE2s；python3 hmac 生成） ----------

    it('Hkdf: extract/expand KAT #1（ikm=0b*22）', 0, () => {
      const prk = Hkdf.extract(hex('000102030405060708090a0b0c'), hex('0b0b0b0b0b0b0b0b0b0b0b0b0b0b0b0b0b0b0b0b0b0b'));
      expectBytes(prk, '57e878130679f9ea85900980b52df2643d043b82f290eb7dd62175dbb04cca4e');
      const okm = Hkdf.expand(prk, hex('f0f1f2f3f4f5f6f7f8f9'), 42);
      expectBytes(okm, '1472c31f2ff768c71b19f8803683ee3b13c1a5fb3ea59c0c3bf0d44a4a40dcd4329d9cd85bbe35a1b3e7');
    });

    it('Hkdf: extract/expand KAT #2（空 salt/空 info）', 0, () => {
      const prk = Hkdf.extract(new Uint8Array(0), ascii('ikm-material-32bytes-padding-0000'));
      expectBytes(prk, '5fb12ff5c37b924fb44a8214cdf2153f8a8583143e1d30f15d07a7026d88d78a');
      const okm = Hkdf.expand(prk, new Uint8Array(0), 32);
      expectBytes(okm, '9e7cce259dc82b789312aaf83108c7e4d89065b8ceaa18525f80cd463a7f511e');
    });

    it('Hkdf: extract/expand KAT #3（64 字节输出跨块）', 0, () => {
      const prk = Hkdf.extract(ascii('saltysalt'), ascii('another ikm'));
      expectBytes(prk, '3ae6a5f342e93da09035e22a09e149e5ddd487a88a7b01f79296d3e7e2541376');
      const okm = Hkdf.expand(prk, ascii('info-string'), 64);
      expectBytes(okm,
        'f3bb96d650c43001332463c1a8e829ab54a4d73a91de1b10c6325f7183753acf' +
        '4b55cfa2d63595270c6c2fee87e073f8f90694250f4b45df2d4aa4a59465ffd3');
    });

    // ---------- WireGuard KDF1/2/3（keyed BLAKE2s 作 MAC） ----------

    it('Hkdf: kdf1/kdf2/kdf3 KAT', 0, () => {
      const key = range(32);
      const input = ascii('wg kdf input');
      const t1 = Hkdf.kdf1(key, input);
      expect(t1.length).assertEqual(1);
      expectBytes(t1[0], 'd64cfe324f5d402a807833d9d4a2ca4ea4f50a3ec8d2fa66b42d212895e79399');
      const t2 = Hkdf.kdf2(key, input);
      expect(t2.length).assertEqual(2);
      expectBytes(t2[0], 'd64cfe324f5d402a807833d9d4a2ca4ea4f50a3ec8d2fa66b42d212895e79399');
      expectBytes(t2[1], 'e3b4f9df38e065a8102b5345baf2e9e2f57f4dfd3c7b228eb8dd22cbb9e7eaaa');
      const t3 = Hkdf.kdf3(key, input);
      expect(t3.length).assertEqual(3);
      expectBytes(t3[0], t1.length > 0 ? 'd64cfe324f5d402a807833d9d4a2ca4ea4f50a3ec8d2fa66b42d212895e79399' : '');
      expectBytes(t3[1], 'e3b4f9df38e065a8102b5345baf2e9e2f57f4dfd3c7b228eb8dd22cbb9e7eaaa');
      expectBytes(t3[2], '29bf6fa7be651859474094edf8318dfc177242dd1d4e660b1d4405be5e4fe37f');
    });
  });
}
