// clan_utils.dart
const Map<String, String> clanAvatarMap = {
  'Brujah': 'assets/clans/brujah.png',
  'Бруха': 'assets/clans/brujah.png',
  'Gangrel': 'assets/clans/gangrel.png',
  'Гангрел': 'assets/clans/gangrel.png',
  'Malkavian': 'assets/clans/malkavian.png',
  'Малкавиан': 'assets/clans/malkavian.png',
  'Nosferatu': 'assets/clans/nosferatu.png',
  'Носферату': 'assets/clans/nosferatu.png',
  'Toreador': 'assets/clans/toreador.png',
  'Тореадор': 'assets/clans/toreador.png',
  'Tremere': 'assets/clans/tremere.png',
  'Тремер': 'assets/clans/tremere.png',
  'Ventrue': 'assets/clans/ventrue.png',
  'Вентру': 'assets/clans/ventrue.png',
  'Tzimish': 'assets/clans/tzim.png',
  'Тзимисх': 'assets/clans/tzim.png',
  'Banu Hakim': 'assets/clans/banu.png',
  'Бану Хаким': 'assets/clans/banu.png',
};

String getClanAvatarPath(String clanName) {
  return clanAvatarMap[clanName] ?? 'assets/clans/default.png';
}