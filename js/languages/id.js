/*!
 * froala_editor v4.6.0 (https://www.froala.com/wysiwyg-editor)
 * License https://froala.com/wysiwyg-editor/terms/
 * Copyright 2014-2025 Froala Labs
 */

(function (global, factory) {
  typeof exports === 'object' && typeof module !== 'undefined' ? factory(require('froala-editor')) :
  typeof define === 'function' && define.amd ? define(['froala-editor'], factory) :
  (factory(global.FroalaEditor));
}(this, (function (FE) { 'use strict';

  FE = FE && FE.hasOwnProperty('default') ? FE['default'] : FE;

  /**
   * Indonesian
   */
  FE.LANGUAGE['id'] = {
    translation: {
      // Place holder
      'Type something': 'Ketik sesuatu',
      // Basic formatting
      'Bold': 'Tebal',
      'Italic': 'Miring',
      'Underline': 'Garis bawah',
      'Strikethrough': 'Coret',
      // Main buttons
      'Insert': 'Memasukkan',
      'Delete': 'Hapus',
      'Cancel': 'Batal',
      'OK': 'Ok',
      'Back': 'Kembali',
      'Remove': 'Hapus',
      'More': 'Lebih',
      'Update': 'Memperbarui',
      'Style': 'Gaya',
      // Font
      'Font Family': 'Jenis Huruf',
      'Font Size': 'Ukuran leter',
      // Colors
      'Colors': 'Warna',
      'Background': 'Latar belakang',
      'Text': 'Teks',
      'HEX Color': 'Warna hex',
      // Paragraphs
      'Paragraph Format': 'Format',
      'Normal': 'Normal',
      'Code': 'Kode',
      'Heading 1': 'Header 1',
      'Heading 2': 'Header 2',
      'Heading 3': 'Header 3',
      'Heading 4': 'Header 4',
      // Style
      'Paragraph Style': 'Paragraf gaya',
      'Inline Style': 'Di barisan gaya',
      // Alignment
      'Align': 'Rate',
      'Align Left': 'Rate kiri',
      'Align Center': 'Rate tengah',
      'Align Right': 'Rata kanan',
      'Align Justify': 'Justifi',
      'None': 'Tak satupun',
      // Lists
      'Ordered List': 'List nomor',
      'Unordered List': 'List simbol',
      // Indent
      'Decrease Indent': 'Turunkan inden',
      'Increase Indent': 'Tambah inden',
      // Links
      'Insert Link': 'Memasukkan link',
      'Open in new tab': 'Buka di tab baru',
      'Open Link': 'Buka tautan',
      'Edit Link': 'Mengedit link',
      'Unlink': 'Menghapus link',
      'Choose Link': 'Memilih link',
      // Images
      'Insert Image': 'Memasukkan gambar',
      'Upload Image': 'Meng-upload gambar',
      'By URL': 'Oleh URL',
      'Browse': 'Melihat-lihat',
      'Drop image': 'Jatuhkan gambar',
      'or click': 'atau klik',
      'Manage Images': 'Mengelola gambar',
      'Loading': 'Pemuatan',
      'Deleting': 'Menghapus',
      'Tags': 'Label',
      'Are you sure? Image will be deleted.': 'Apakah Anda yakin? Gambar akan dihapus.',
      'Replace': 'Mengganti',
      'Uploading': 'Gambar upload',
      'Loading image': 'Pemuatan gambar',
      'Display': 'Pameran',
      'Inline': 'Di barisan',
      'Break Text': 'Memecah teks',
      'Alternative Text': 'Teks alternatif',
      'Change Size': 'Ukuran perubahan',
      'Width': 'Lebar',
      'Height': 'Tinggi',
      'Something went wrong. Please try again.': 'Ada yang salah. Silakan coba lagi.',
      'Image Caption': 'Keterangan gambar',
      'Advanced Edit': 'Edit lanjutan',
      // Video
      'Insert Video': 'Memasukkan video',
      'Embedded Code': 'Kode tertanam',
      'Paste in a video URL': 'Paste di url video',
      'Drop video': 'Jatuhkan video',
      'Your browser does not support HTML5 video.': 'Browser Anda tidak mendukung video html5.',
      'Upload Video': 'Mengunggah video',
      // Tables
      'Insert Table': 'Sisipkan tabel',
      'Table Header': 'Header tabel',
      'Remove Table': 'Hapus tabel',
      'Table Style': 'Gaya tabel',
      'Horizontal Align': 'Menyelaraskan horisontal',
      'Row': 'Baris',
      'Insert row above': 'Sisipkan baris di atas',
      'Insert row below': 'Sisipkan baris di bawah',
      'Delete row': 'Hapus baris',
      'Column': 'Kolom',
      'Insert column before': 'Sisipkan kolom sebelumSisipkan kolom sebelum',
      'Insert column after': 'Sisipkan kolom setelah',
      'Delete column': 'Hapus kolom',
      'Cell': 'Sel',
      'Merge cells': 'Menggabungkan sel',
      'Horizontal split': 'Perpecahan horisontal',
      'Vertical split': 'Perpecahan vertikal',
      'Cell Background': 'Latar belakang sel',
      'Vertical Align': 'Menyelaraskan vertikal',
      'Top': 'Teratas',
      'Middle': 'Tengah',
      'Bottom': 'Bagian bawah',
      'Align Top': 'Menyelaraskan atas',
      'Align Middle': 'Menyelaraskan tengah',
      'Align Bottom': 'Menyelaraskan bawah',
      'Cell Style': 'Gaya sel',
      // Files
      'Upload File': 'Meng-upload berkas',
      'Drop file': 'Jatuhkan berkas',
      // Emoticons
      'Emoticons': 'Emoticon',
      'Grinning face': 'Sambil tersenyum wajah',
      'Grinning face with smiling eyes': 'Sambil tersenyum wajah dengan mata tersenyum',
      'Face with tears of joy': 'Hadapi dengan air mata sukacita',
      'Smiling face with open mouth': 'Tersenyum wajah dengan mulut terbuka',
      'Smiling face with open mouth and smiling eyes': 'Tersenyum wajah dengan mulut terbuka dan tersenyum mata',
      'Smiling face with open mouth and cold sweat': 'Tersenyum wajah dengan mulut terbuka dan keringat dingin',
      'Smiling face with open mouth and tightly-closed eyes': 'Tersenyum wajah dengan mulut terbuka dan mata tertutup rapat',
      'Smiling face with halo': 'Tersenyum wajah dengan halo',
      'Smiling face with horns': 'Tersenyum wajah dengan tanduk',
      'Winking face': 'Mengedip wajah',
      'Smiling face with smiling eyes': 'Tersenyum wajah dengan mata tersenyum',
      'Face savoring delicious food': 'Wajah menikmati makanan lezat',
      'Relieved face': 'Wajah Lega',
      'Smiling face with heart-shaped eyes': 'Tersenyum wajah dengan mata berbentuk hati',
      'Smiling face with sunglasses': 'Tersenyum wajah dengan kacamata hitam',
      'Smirking face': 'Menyeringai wajah',
      'Neutral face': 'Wajah Netral',
      'Expressionless face': 'Wajah tanpa ekspresi',
      'Unamused face': 'Wajah tidak senang',
      'Face with cold sweat': 'Muka dengan keringat dingin',
      'Pensive face': 'Wajah termenung',
      'Confused face': 'Wajah Bingung',
      'Confounded face': 'Wajah kesal',
      'Kissing face': 'wajah mencium',
      'Face throwing a kiss': 'Wajah melempar ciuman',
      'Kissing face with smiling eyes': 'Berciuman wajah dengan mata tersenyum',
      'Kissing face with closed eyes': 'Berciuman wajah dengan mata tertutup',
      'Face with stuck out tongue': 'Muka dengan menjulurkan lidah',
      'Face with stuck out tongue and winking eye': 'Muka dengan menjulurkan lidah dan mengedip mata',
      'Face with stuck out tongue and tightly-closed eyes': 'Wajah dengan lidah terjebak dan mata erat-tertutup',
      'Disappointed face': 'Wajah kecewa',
      'Worried face': 'Wajah Khawatir',
      'Angry face': 'Wajah Marah',
      'Pouting face': 'Cemberut wajah',
      'Crying face': 'Menangis wajah',
      'Persevering face': 'Tekun wajah',
      'Face with look of triumph': 'Hadapi dengan tampilan kemenangan',
      'Disappointed but relieved face': 'Kecewa tapi lega wajah',
      'Frowning face with open mouth': 'Sambil mengerutkan kening wajah dengan mulut terbuka',
      'Anguished face': 'Wajah sedih',
      'Fearful face': 'Wajah Takut',
      'Weary face': 'Wajah lelah',
      'Sleepy face': 'wajah mengantuk',
      'Tired face': 'Wajah Lelah',
      'Grimacing face': 'Sambil meringis wajah',
      'Loudly crying face': 'Keras menangis wajah',
      'Face with open mouth': 'Hadapi dengan mulut terbuka',
      'Hushed face': 'Wajah dipetieskan',
      'Face with open mouth and cold sweat': 'Hadapi dengan mulut terbuka dan keringat dingin',
      'Face screaming in fear': 'Hadapi berteriak dalam ketakutan',
      'Astonished face': 'Wajah Kaget',
      'Flushed face': 'Wajah memerah',
      'Sleeping face': 'Tidur face',
      'Dizzy face': 'Wajah pusing',
      'Face without mouth': 'Wajah tanpa mulut',
      'Face with medical mask': 'Hadapi dengan masker medis',
      // Line breaker
      'Break': 'Memecah',
      // Math
      'Subscript': 'Subskrip',
      'Superscript': 'Superskrip',
      // Full screen
      'Fullscreen': 'Layar penuh',
      // Horizontal line
      'Insert Horizontal Line': 'Sisipkan Garis Horizontal',
      // Clear formatting
      'Clear Formatting': 'Menghapus format',
      // Save
      'Save': 'Menyimpan',
      // Undo, redo
      'Undo': 'Batal',
      'Redo': 'Ulang',
      // Select all
      'Select All': 'Pilih semua',
      // Code view
      'Code View': 'Melihat kode',
      // Quote
      'Quote': 'Kutipan',
      'Increase': 'Meningkat',
      'Decrease': 'Penurunan',
      // Quick Insert
      'Quick Insert': 'Memasukkan cepat',
      // Spcial Characters
      'Special Characters': 'Karakter spesial',
      'Latin': 'Latin',
      'Greek': 'Yunani',
      'Cyrillic': 'Kyrillic',
      'Punctuation': 'Tanda baca',
      'Currency': 'Mata uang',
      'Arrows': 'Panah',
      'Math': 'Matematika',
      'Misc': 'Misc',
      // Print.
      'Print': 'Mencetak',
      // Spell Checker.
      'Spell Checker': 'Pemeriksa ejaan',
      // Help
      'Help': 'Membantu',
      'Shortcuts': 'Jalan pintas',
      'Inline Editor': 'Editor inline',
      'Show the editor': 'Tunjukkan editornya',
      'Common actions': 'Tindakan umum',
      'Copy': 'Salinan',
      'Cut': 'Memotong',
      'Paste': 'Pasta',
      'Basic Formatting': 'Format dasar',
      'Increase quote level': 'Meningkatkan tingkat kutipan',
      'Decrease quote level': 'Menurunkan tingkat kutipan',
      'Image / Video': 'Gambar / video',
      'Resize larger': 'Mengubah ukuran lebih besar',
      'Resize smaller': 'Mengubah ukuran lebih kecil',
      'Table': 'Meja',
      'Select table cell': 'Pilih sel tabel',
      'Extend selection one cell': 'Memperpanjang seleksi satu sel',
      'Extend selection one row': 'Perpanjang pilihan satu baris',
      'Navigation': 'Navigasi',
      'Focus popup / toolbar': 'Fokus popup / toolbar',
      'Return focus to previous position': 'Kembali fokus ke posisi sebelumnya',
      // Embed.ly
      'Embed URL': 'Embed url',
      'Paste in a URL to embed': 'Paste di url untuk menanamkan',
      // Word Paste.
      'The pasted content is coming from a Microsoft Word document. Do you want to keep the format or clean it up?': 'Konten yang disisipkan berasal dari dokumen kata microsoft. apakah Anda ingin menyimpan format atau membersihkannya?',
      'Keep': 'Menjaga',
      'Clean': 'Bersih',
      'Word Paste Detected': 'Kata paste terdeteksi',
      // Character Counter
      'Characters': 'Karakter',
      // More Buttons
      'More Text': 'Lebih banyak teks',
      'More Paragraph': 'Lebih banyak paragraf',
      'More Rich': 'Lebih banyak Kaya',
      'More Misc': 'Lebih banyak Lain-lain'
    },
    direction: 'ltr'
  };

})));
//# sourceMappingURL=id.js.map
