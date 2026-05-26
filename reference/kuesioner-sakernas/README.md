# Kuesioner Sakernas (1997-2024)

Arsip kuesioner **Survei Angkatan Kerja Nasional** dari BPS untuk tiap tahun
sejak 1997. Berguna untuk:

- **Verifikasi variabel** — kalau angka di dasbor terasa janggal, periksa
  kuesioner tahun yang relevan untuk melihat persis pertanyaan apa yang
  diajukan ke responden dan bagaimana opsi jawaban terstruktur.
- **Memahami diskontinuitas variabel** — beberapa pertanyaan berubah lintas
  tahun (mis. skema kode okupasi pre-2014 vs KBJI 2014; ICLS-17 informality
  baru bisa diturunkan 2019+). Kuesioner memperlihatkan perubahan tepatnya.
- **Membangun derivasi baru** — kalau ingin menambah variabel di Stata
  cleaning step, kuesioner adalah rujukan otoritatif untuk struktur block
  pertanyaan.

## Konvensi nama file

```
<year>_SAK.pdf            ← satu kuesioner tahunan (1997-2006, 2011-2016, 2020-2024)
<year>_2_SAK.pdf          ← edisi Februari (2007-2010, 2017-2019)
<year>_8_SAK.pdf          ← edisi Agustus / tahunan konsolidasi (2007-2010, 2017-2019)
```

Tahun yang punya dua edisi (Februari + Agustus): 2007, 2008, 2009, 2010,
2017, 2018, 2019. Untuk tahun-tahun tersebut, dasbor ini terutama memakai
edisi Agustus (yang lebih komprehensif) — silakan periksa kuesioner edisi
Februari kalau ada pertanyaan tentang variabel yang hanya muncul di edisi
itu.

## Sumber

Diunduh dari BPS (Badan Pusat Statistik) — kuesioner Sakernas adalah dokumen
publik, dapat didistribusikan ulang. Sakernas microdata-nya yang restricted
(individual-level), kuesioner blanko-nya bebas.

## Bahasa

Semua kuesioner dalam **Bahasa Indonesia**. Untuk istilah teknis kunci
(LFPR, EPR, informalitas, ICLS-17, dst.), lihat
[`../../docs/METHODOLOGY.md`](../../docs/METHODOLOGY.md) yang menjelaskan
padanan Bahasa Inggris-nya.

---

**Kuesioner Sakernas adalah hak cipta BPS** dan diarsipkan di sini untuk
kepentingan reproducibility riset. Permintaan koreksi atau versi yang lebih
baru: <https://www.bps.go.id>.
