#!/usr/bin/env python3
from __future__ import annotations

import base64
import binascii
from decimal import Decimal, InvalidOperation
import hashlib
import json
from pathlib import Path
import re
import struct
import subprocess
import sys
import tempfile
import zlib

SOURCE_WIDTH = 512
SOURCE_HEIGHT = 512
PALETTE_COLORS = 16
RAW_SHA256 = "31df8a4f2570c3e515e6ed5a9fa01cd4cae89596869ed82a1ee601a07835f147"
ICON_PAYLOAD_B85 = (
    'c-rlqJCY^2t%mb)>X4bthbjMF`#KsaBpF(TmZ7c4SA?7yZRl=8wjyRESIo@QHQl4`sPjk?0Qvn+S5;fUPXIqaCi(Bb|K?vmeD~82'
    'zy0a^?|%ILw?BUW-A~{D`kz1i{vUt)!~g%~cYpo!cYpfh|NP(o{wfTvY1*b~-T(jq00000000000000000000000000000000000'
    '000000000000000000000Dx5Jx0~;prgJ;G{g<}KFEwDJ-uqz~$MBAE90u>>I%x4v;c@T$5Q(4Wd0y6cEb-SVE`z~4@<73n?;`ip'
    '7tDWwZ4r!vBMX!m`c1c!zkYz*5+Df_7y5UQ|GoqUPZB68_Wc;Xnf1SdWey`NpeXj&2eGdJsz3p$KW6@i**{jm;79@Hga1kPZ!4f<'
    '1=tS$aaz`=u}rZD;6<}|CHUV{04ku);D1j6r~sSv`*B`Rz#Kdaz#{$O6#8Qdh&2Fz+AICby0QSOrGGk&{)mYMV2%FuR7_)sSL>xe'
    's=$#9P%-_K07J_E+}h6qFxU8{pnqM%z#O1r`ePf&AV@zh<Gd!qJUaFQv}?a~^wR{G(0*$|Oh^FL=v}Jf|1JTj0JUcSqXIAotTy{o'
    '0hGgyOKSd?;PA87>_5zFa?FeY^@_hW1CW3<hd)CAwc+oxgg*(O?(io8XchmN!k+|CYwu4Bpcq~H-v8$r07F1^;qSABKSMx`>TjI$'
    '@xPz|wc!$$eEhErftBH!GyPKl>TUih07}dMl9hit09D8~`+Y9}{)*SD9R4r@BK;!(;GYISRrkMU1`~jKyMF|rHu)#OKNFy8r$00R'
    'waY&m0QiT0_y_g!kN(r6|MT;|2KcX=f7}lL0R92|gX;7@CxGbx0sI5_2g3Xh@L#q5AF}WNv;V6ISI&P_jqJz&Isc^#UC1o}!UeBa'
    '+yEf|lr;dE4*+rpl&%IKw*W-`>4M8F0J#FJY5_p`uUh~x{i%BbF!2&t%>{tX|GEnR>A&s*Froex7JwP`U-Jkk-ySf-AC1U%0W?oQ'
    ')tvxPe>!o=lmH0-suKX=Uv&bY`q!NR5dT%r02UsAu6hU<*!iis0wDgh4}s>i*`H&-n!~?wX%oOSxQ6_%mVG~lDQOG1%whB$D?p?6'
    'Yld;kumw0z<Iu7Ft1kHcIOW>^nMRrbZMts=InVzDQh=)5@5bEUe~gX=posqb_rJ3M)Zmhz{(S-9c@+?N{ee$F6)FGxm%p$Rs0c1B'
    'GW@Rr2~chJrvfO^{`s%|VKZ1$_>Z$3|0Do$@#m*i5PSz*bNKTmSk={^1W<eUqX2}%-wB657eUq9`;!0^pc5PY@im}^=5Lt9>1P)}'
    'QvJz?KP_Or%^#Nm)vo?ffRgG@L;Bx72<Mw15%uS%RRvIhb<X}M0HU~rMF;<k0IE*^6o9(ZKO=z3(?12E?(|Oqs5|}B0Z0sg6s3O('
    'Kz3X;rGJir<xl^^tciaLK=$&lDgE;xP-ZAN`1i{Kz;oa^yT4)5#Xt8#)|~zs0ao4p(E--o{V@WpyZb``)L#A(09kPft2*!@SibI0'
    'U-?G>)Ls4=0oPsr5df8!e*{3?<sSi1clk#E)Ls4&0NJ2#_|FzVMqG84e-44wUH;husJr|l0IKJoLx4Hp!m1R3Lx9yzf0zK(F8>gK'
    'b(enxVD<bX0Be?i2*8@Be+a<Z<sSmD?(&ZSgn#mXVswh-A6vi~<ezH(`3$_?=`RgH?ed=npl<m`0|5W<pSJ!7)%>r#1(6m`wftuX'
    'AbI;Y>E@p^z-iO}pqzgifSTJs_)jkXmGe&nP;>hS|L_n06}SJf0pti^LR^%$|Jx2Qw}7N;|DAgN*#WM3{KEj~1@!HPCSw2LD|xgv'
    '!2j1y0DNp&^~^V&^L~gJBes9NcU|;XZ)*JaUjv}eEgOEe%>B}`nz?T}zxgJFX`0_LO;ZTbUEY1>DfQ#OFZti8zt6II$#<KBqI<sD'
    'P0#b@D&IA|8UAkrfDbK;t6;aRV!6;ZF*>4$KJe(gJ8Fv+GyLCYSzH94EUPf|n@e=jeAhhZa8%Q(AOG(Iz`k{NTejXTtB-v@gz14{'
    '-V(Ebx558r+5DhoU0WIZF+d(pt<z|M|GPu~%Op_G3V4qFBUBdk{7=tWR?iBE)iJ0KV~K?m>s$Fsu<v01TU8*8uJjbp`f*yI`kO0Y'
    'C^`iY{2v#Af>S{2#tDu;P636|-*|%mo)j>2Mb?032vq*NwvbD#0kQOx`|sXEDDDtRf1&h0A_59q0KFS2{f~%%vK9dJKfVA8x=9B5'
    'tIhzi_CtTg3!sDknioJr<M(VESi-kNE%ZOX0PKHE*!lpGPfr5P?*&BZ&(Qak1z=nPG-$sUHDFKiM*>*Q{+=zrnk4|)|8*Fy0A&AD'
    'DuCGp;K=?p_W%aI)-=%rj5Z&Y=^c}wniBxwf7%eh5&ramg#SlMdCu{9=rYf_zhJVc00hE++OOJ~=Q-g5o5DEeKgVuR0SNT|u~Tl`'
    'c9m4vSHW^>%+K$aHVK?(FnFtQC$R6gjmq|W_T244v9Mpe^)l~U%n!$PbZswk2er9dB}Hy(e7}3G-&etL@7}%+!tMUGdr3cNKX|_p'
    '|LK;dUgAK5xgns;<o_41Z}rDIXxz_NONQ{-YWNb<@qb@j(zx^9D`;!2wSY3s-?uJb-WS4t|7z#9#c*85dE7O6(7iJrDc@rKxTUr4'
    'zg5_n0cqX&xhGBb{jnN8t%%#5ya(kUZ?*Matz~TdW_W&4YN~0g0CYk-f9Y@Emr4J|3V_%>?dhLilRD09>R~ytt)JwB60svKrba+='
    '=e|-4071(PeGJrzZT+Pd08-`OlmO`EzWGV*CAm#)LjpkX+-Kr4Dfj@Dp$UNC$)6?d_Y#sPnu8tw1&{rw6@a3anGt}Juk=nnt!1km'
    '|7P}pJHeBGX&Zn}a%Ed-07OrIruCBK`@?1$fU7T-|2OzoJpE7aB~i;p_`d@wy>x|t<xMjDS3UlL|JwOaIsg{UZ14~N@K63n|G_`~'
    'pGf|P|H|h-4*r?{GXJf3|7U^!j~f8?e{0_Vl|BEF*fPoUA9l|F$esV={8!xrpkmK|8u|c8&`UGtzZEn9<$nKh;roxf8UQH)I3*TI'
    'g5Q4`x&n&tKWmnMn*iYZ?|S8*pa7VY&qy5iKPa96P042@a+X=T08DBEkp8tSq0(mT4tSw0;0#GpsI*zT090n9WXdoiZ-gwfbpfzQ'
    '0a$W8mMBsH%sl}j^6c}RWrx&-A`4pqX);fcNQ{8&Jpw87{zIYK*5VtG`4wQUAjxl;#TVeRCxC1d(sC_3d8;&UnB;4bawh<r4?t!P'
    'lZ-)<-Lme@A}(3OB<F-AZvwFT0Cd(c$tsaETV^x-^M*;@4msxxAb6wizvmnRX3mircY$V$kN@W01z5&Qp|x!pU2m5EH<zgb<j;}0'
    'YMWK@m$d>2JdhqOTe671#xVPh&+}IHG!9+U7iyVnY!-ml4dXQD$&zzcKegR3hHRDvlPe(lC`=irB+DHA)aGJ8vt^?<xBc(4`sfIi'
    'Fm!#fmRXX4?IpjDwn&-A)O|pI8G^(C;PjTAs*R<-l8S+n)J?6EvTO-v=0LGE61@K*<pPjf*jsWlvH&u5#sUMA-i@=UWfm4d??y@b'
    'Q_ccq>5rCKm<2Y%PD*!HUiMz&!!q@Q0NKlbQ_f6fpEWTu4eni7q`j2rD9~k8V43y`Af6+W?FP3hEK~j+STA|?Z`v?%DlAie8bn<D'
    'B?}W3iEUMW4N$8i{1bc$+Uv2bA^h(NlX5NV3IFU0z^SoJaRSg2Bxm0Pt)=>_9s>1xg5>N3pkb<!OxqL~Bqx6ks9>o1xn)Yf2kI0B'
    '$+>qyb)zoJR3-pbL2~M>y!WMAR;c<rxdl{bna10IdLL9d=|lzSlv$>-1yrT}PE~-)3Y$^|s7oWAsQ?>=mZ?*KtydN#r=>}Cg-xXb'
    ')TWVkozxXs*i;?^aA8r$|2c1g>MLvt&jG2^NT;RAt1s2E($oJruR$qH|Es=TU>6iR>68MXG5xD604me}DQQw=`d3!~bf*6^3V_b^'
    'udM*+O#f#T0G;VySpjHuCdm`hWM8ahMbG}<@#>^puVtD>KwVf?tp%WeQP}9UtkskLm6re4_W;VZtcvvi>L#$#zV_Gy(8IslB>8HY'
    'RBf4-Q$W2_n<QWDlP-!aQ*#bnaguzoPrCY2EvsSpcT1C9k-|n%2dKCEdvye;x%{i?0DG^vNWNAkopQ?>9pzthl6<8DR4r`OJPWD2'
    '{J*jXsNOOadw`wlB>9Q}=v0?~C3}FapLFy8e3|shSGI}{P<M~?N|{t%{*?#-?M3o=0bsx~1tVbX<^OpBpuPO75CE-L&;PRmz!hs*'
    'J>CBcWm0|lS0MoO7s+Su0yAKlf(bwq7WH0w?hsfrTChx50QCCH|FbgbV!$$S0brm=J~=13`cf^cYWj1?q^?lQPP*ct%mZ?t%cNp0'
    '6P^G$14Z(=2~cN(f8j%btvA8{Gcw5)Ygt{>pC{)eCWNi{1gNpXe^;nw!iPX@h@@w{WX3X40cfL0J|h4-Bm9dBz}_3-|8be*inXjh'
    '`S*lOGBN!Vp8z&?`0om}OmqThVT<(UrAwLePgVeSMvCO)0<bf~zu*>d@9gmZpiI7)u}n|^wpK*a!(QqQStcg{?TDmD8vrBIU*QR`'
    'DgL`cEfbso+mZj#ONGjR$p)Y?Ba$9%04(t@)&Lli|Bp5Rmtco~u?C>^hWLNXORiYUYCHS;luW*QLzam(fR;q^WBl7%*#Z7fZU9YL'
    'Ce{F2YX2VF0kS0j<vs#zf+a6azEu9D8bC`T`LO{&XNrHJBVfHT{vYtt#gt`24Pft!^^%+5zogyY2OGevEz5)k0IjJe3I3~Y{~zMt'
    ')c9v>0O9}C0g$oGCNu!DHU3$b`wvPRvkd-E9soAuYRfW_6Ck#RWa~N=Ync%L!B&*qKL9qjvPA~K_V~Yd0NlZUapV7z`Ip%MD473X'
    'jsFJzKj#1LD1m?Yhky8ofB1)g_=kV^hky8of95~Tf0+L=|FyYG!v0Uy`~U3!a{h<&Kb-&M{O3vMzd8S}L;jC^|8s7W?D+nxI4_m^'
    '{ioC`;3a?mZ^|;E3*gGV|EFBbP89$p-~UGXFDgwgkM+owZnl+s13q>DOQAvHinXjt1@Lf-+zwXWe;OrUfNpFofO)(Wy0oKZq7Ohf'
    'gMmajJ>#UdSj)~W0X`^~N=q2J=PVlySSCz=bdwt=#euR+<FmWt(K6L*J6hJf$)j()+7+<OF+|!@EpzRg3bf5IPP4|?f7M5-Eo<J?'
    'ppB6dW?i8&PvZ$b(ra1&rU}tcTc|8*Toht;Y)iGQYu?nMZ#G9Mh?Qk?Q4Ek4%d#hd-BE(Ua(Kv}?xJ3SWplJlG5PO~a>L=NMS}ZC'
    'ev`&Un`Orum?c(qNN3sEj%sh7%C`t&aBOkEd#F#F;67P4=d^6+UYX+ia1C^RxVb8!uXg|J4swaP|7;BuYT4PiMpy0e5`A^Lvo`k}'
    '{u!biZknrvWkUkXmT1{5W?7O<aP!r+4yN5(%PX|+ydUmyn}6D?9?Ry}ESujg^OBaOikRrE=&d6k-28RVTG%~vupXVWd&f1qdwMmN'
    'bvMh#M=V>G<?EJ}#Qc}eI=t0%$4b~7wl9Wvr+tR$@XPL*=$g$pH|J>d&MB4^%lm&P&ue@5Ys(7JW&ZHm;kesR+aEtUW@o)OlIq?q'
    '>+ZFz7TUkH7_Of=?Ps?{zx3u4Ua6J=0000000000000000000000000000000000000000000000000000000000000000000000'
    '000000000008k(P14S&pA^'
)


def fail(message: str) -> "NoReturn":
    raise RuntimeError(message)


def png_chunk(kind: bytes, data: bytes) -> bytes:
    crc = binascii.crc32(kind)
    crc = binascii.crc32(data, crc) & 0xFFFFFFFF
    return struct.pack(">I", len(data)) + kind + data + struct.pack(">I", crc)


def write_source_png(path: Path) -> None:
    compressed = base64.b85decode(ICON_PAYLOAD_B85.encode("ascii"))
    raw = zlib.decompress(compressed)
    actual_sha256 = hashlib.sha256(raw).hexdigest()
    if actual_sha256 != RAW_SHA256:
        fail(
            "Embedded icon payload checksum mismatch: "
            f"expected {RAW_SHA256}, got {actual_sha256}"
        )

    palette_bytes = PALETTE_COLORS * 3
    expected_size = palette_bytes + SOURCE_WIDTH * SOURCE_HEIGHT
    if len(raw) != expected_size:
        fail(f"Embedded icon payload has {len(raw)} bytes; expected {expected_size}")

    palette_raw = raw[:palette_bytes]
    indices = raw[palette_bytes:]
    palette = [palette_raw[i : i + 3] for i in range(0, palette_bytes, 3)]

    scanlines = bytearray()
    for y in range(SOURCE_HEIGHT):
        scanlines.append(0)  # PNG filter: None
        start = y * SOURCE_WIDTH
        end = start + SOURCE_WIDTH
        for index in indices[start:end]:
            if index >= PALETTE_COLORS:
                fail(f"Embedded icon contains invalid palette index {index} at row {y}")
            scanlines.extend(palette[index])

    ihdr = struct.pack(
        ">IIBBBBB",
        SOURCE_WIDTH,
        SOURCE_HEIGHT,
        8,  # bit depth
        2,  # truecolor RGB; deliberately no alpha channel
        0,
        0,
        0,
    )
    png = (
        b"\x89PNG\r\n\x1a\n"
        + png_chunk(b"IHDR", ihdr)
        + png_chunk(b"IDAT", zlib.compress(bytes(scanlines), 9))
        + png_chunk(b"IEND", b"")
    )
    path.write_bytes(png)


def sips_properties(path: Path) -> dict[str, str]:
    output = subprocess.check_output(
        ["sips", "-g", "pixelWidth", "-g", "pixelHeight", "-g", "hasAlpha", str(path)],
        text=True,
    )
    properties: dict[str, str] = {}
    for line in output.splitlines():
        stripped = line.strip()
        if ": " not in stripped:
            continue
        key, value = stripped.split(": ", 1)
        if key in {"pixelWidth", "pixelHeight", "hasAlpha"}:
            properties[key] = value

    missing = {"pixelWidth", "pixelHeight", "hasAlpha"} - properties.keys()
    if missing:
        fail(f"sips did not report {sorted(missing)} for {path}. Output:\n{output}")
    return properties


def parse_pixel_size(item: dict[str, object], index: int) -> int:
    filename = item.get("filename")
    size = item.get("size")
    scale = item.get("scale")
    if not isinstance(filename, str) or not filename:
        fail(f"AppIcon image entry {index} has no non-empty filename: {item!r}")
    if not isinstance(size, str) or not isinstance(scale, str):
        fail(f"AppIcon image entry {index} has invalid size or scale: {item!r}")

    size_match = re.fullmatch(r"([0-9]+(?:\.[0-9]+)?)x([0-9]+(?:\.[0-9]+)?)", size)
    scale_match = re.fullmatch(r"([0-9]+(?:\.[0-9]+)?)x", scale)
    if size_match is None or scale_match is None:
        fail(f"AppIcon image entry {index} has unsupported size/scale: {size!r}, {scale!r}")

    try:
        width_points = Decimal(size_match.group(1))
        height_points = Decimal(size_match.group(2))
        scale_value = Decimal(scale_match.group(1))
    except InvalidOperation as exc:
        raise RuntimeError(f"AppIcon image entry {index} has non-decimal size/scale") from exc

    if width_points != height_points:
        fail(f"AppIcon image entry {index} is not square: {size!r}")
    pixels = width_points * scale_value
    if pixels != pixels.to_integral_value():
        fail(f"AppIcon image entry {index} resolves to non-integer pixels: {pixels}")

    pixel_size = int(pixels)
    if pixel_size < 1 or pixel_size > 1024:
        fail(f"AppIcon image entry {index} resolves to unsupported size {pixel_size}px")
    return pixel_size


def validate_opaque_square(path: Path, expected_pixels: int) -> None:
    props = sips_properties(path)
    if props["pixelWidth"] != str(expected_pixels) or props["pixelHeight"] != str(expected_pixels):
        fail(
            f"Generated icon {path} has {props['pixelWidth']}x{props['pixelHeight']}; "
            f"expected {expected_pixels}x{expected_pixels}"
        )
    if props["hasAlpha"].strip().lower() != "no":
        fail(f"Generated icon {path} unexpectedly contains an alpha channel")


def main() -> None:
    if len(sys.argv) != 2:
        raise SystemExit(
            "Usage: install_ios_app_icon.py "
            "<ios/Runner/Assets.xcassets/AppIcon.appiconset>"
        )

    iconset_dir = Path(sys.argv[1])
    contents_path = iconset_dir / "Contents.json"
    if not iconset_dir.is_dir():
        fail(f"AppIcon asset directory does not exist: {iconset_dir}")
    if not contents_path.is_file():
        fail(f"AppIcon Contents.json does not exist: {contents_path}")

    contents = json.loads(contents_path.read_text(encoding="utf-8"))
    images = contents.get("images")
    if not isinstance(images, list) or not images:
        fail(f"AppIcon Contents.json has no non-empty images list: {contents_path}")

    with tempfile.TemporaryDirectory(prefix="minapp-ios-icon-") as temp_dir:
        source_path = Path(temp_dir) / "minapp-icon-512.png"
        write_source_png(source_path)
        validate_opaque_square(source_path, SOURCE_WIDTH)

        generated = 0
        seen_filenames: set[str] = set()
        for index, item in enumerate(images):
            if not isinstance(item, dict):
                fail(f"AppIcon image entry {index} is not an object: {item!r}")

            filename = item.get("filename")
            pixel_size = parse_pixel_size(item, index)
            assert isinstance(filename, str)
            if filename in seen_filenames:
                fail(f"AppIcon Contents.json repeats filename {filename!r}")
            seen_filenames.add(filename)

            target = iconset_dir / filename
            subprocess.run(
                ["sips", "-z", str(pixel_size), str(pixel_size), str(source_path), "--out", str(target)],
                check=True,
            )
            if not target.is_file():
                fail(f"sips completed without creating expected icon: {target}")
            validate_opaque_square(target, pixel_size)
            generated += 1

    if generated != len(images):
        fail(f"Generated {generated} icons for {len(images)} AppIcon entries")
    print(f"Installed MinApp icon into {generated} AppIcon assets")


if __name__ == "__main__":
    main()
