#if os(macOS)
import Testing
@testable import Ghostty

struct SkinRequestTests {
    @Test func decodesValidRequests() {
        #expect(SkinRequest.decode("{\"v\":1,\"op\":\"preview\",\"skin\":\"arca\"}")
            == SkinRequest(op: .preview, skin: "arca"))
        #expect(SkinRequest.decode("{\"v\":1,\"op\":\"set\",\"background\":\"#3A0F14\",\"texture\":\"grid\",\"opacity\":0.25}")
            == SkinRequest(op: .set, background: RGB(hex: "#3a0f14"), texture: "grid", opacity: 0.25))
        #expect(SkinRequest.decode("{\"v\":1,\"op\":\"reset\"}") == SkinRequest(op: .reset))
        #expect(SkinRequest.decode("{\"v\":1,\"op\":\"cancel\",\"future\":\"field\"}") == SkinRequest(op: .cancel))
    }

    @Test(arguments: [
        "{\"v\":2,\"op\":\"set\"}",
        "{\"op\":\"set\"}",
        "{\"v\":1,\"op\":\"delete\"}",
        "{\"v\":1,\"op\":\"set\",\"texture\":\"../../etc/passwd\"}",
        "{\"v\":1,\"op\":\"set\",\"texture\":\"/tmp/x.png\"}",
        "{\"v\":1,\"op\":\"set\",\"skin\":\"a/b\"}",
        "{\"v\":1,\"op\":\"set\",\"background\":\"red\"}",
        "{\"v\":1,\"op\":\"set\",\"opacity\":1.5}",
        "{\"v\":1,\"op\":\"set\",\"opacity\":-0.1}",
        "not json",
        "",
    ])
    func rejects(_ json: String) {
        #expect(SkinRequest.decode(json) == nil)
    }

    @Test func rejectsOversizedPayloads() {
        let padding = String(repeating: " ", count: SkinsConstants.maxPayloadBytes)
        #expect(SkinRequest.decode(#"{"v":1,"op":"reset"}"# + padding) == nil)
    }
}
#endif
