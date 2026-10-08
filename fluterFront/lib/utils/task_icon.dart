import 'package:flutter/material.dart';

const _accentMap = {
  'á': 'a',
  'à': 'a',
  'â': 'a',
  'ä': 'a',
  'é': 'e',
  'è': 'e',
  'ê': 'e',
  'ë': 'e',
  'í': 'i',
  'ì': 'i',
  'î': 'i',
  'ï': 'i',
  'ó': 'o',
  'ò': 'o',
  'ô': 'o',
  'ö': 'o',
  'ú': 'u',
  'ù': 'u',
  'û': 'u',
  'ü': 'u',
  'ñ': 'n',
  'ç': 'c',
  'ß': 'ss',
};

final _accentRegex = RegExp(r'[áàâäéèêëíìîïóòôöúùûüñçß]');

String _stripAccents(String text) {
  return text.replaceAllMapped(_accentRegex, (m) => _accentMap[m[0]] ?? m[0]!);
}

class _TaskIconRule {
  final IconData icon;
  final RegExp regex;

  _TaskIconRule(this.icon, List<String> keywords)
      : regex = RegExp(
          r'\b(?:' +
              (keywords.toSet().toList()
                    ..sort((a, b) => b.length.compareTo(a.length)))
                  // Short keywords match whole words only (plural allowed),
                  // or "lit" would fire on "little", "bed" on "bedroom",
                  // "car" on "cart"; longer ones match as word prefixes.
                  .map((k) => k.length <= 4
                      ? '${RegExp.escape(k)}(?:s|es)?\\b'
                      : RegExp.escape(k))
                  .join('|') +
              r')',
        );
}

final List<_TaskIconRule> _rules = [
  // 1. medication
  _TaskIconRule(Icons.medication_rounded, const [
    'medication', 'medicine', 'pill',
    'medicacion', 'medicina', 'pastilla',
    'medicament',
    'medikament', 'tablette',
  ]),
  // 2. doctor
  _TaskIconRule(Icons.medical_services_rounded, const [
    'doctor', 'appointment', 'clinic', 'hospital',
    'medico', 'cita', 'clinica',
    'medecin', 'rendez-vous',
    'arzt', 'termin', 'klinik',
  ]),
  // 3. pet
  _TaskIconRule(Icons.pets_rounded, const [
    'pet', 'dog', 'cat', 'vet',
    'mascota', 'perro', 'gato',
    'animal', 'chien',
    'haustier', 'hund', 'katze',
  ]),
  // 4. pick-up
  _TaskIconRule(Icons.backpack_rounded, const [
    'pick-up', 'pickup', 'pick up', 'collect',
    'recoger',
    'recuperer',
    'abholen',
  ]),
  // 5. drop-off
  _TaskIconRule(Icons.school_rounded, const [
    'drop-off', 'dropoff', 'drop off', 'school', 'daycare', 'nursery',
    'dejar', 'colegio', 'escuela', 'guarderia',
    'deposer', 'ecole', 'creche',
    'bringen', 'schule', 'kita',
  ]),
  // 6. homework
  _TaskIconRule(Icons.menu_book_rounded, const [
    'homework', 'study',
    'deberes', 'estudiar',
    'devoirs',
    'hausaufgaben', 'lernen',
  ]),
  // 7. read
  _TaskIconRule(Icons.auto_stories_rounded, const [
    'read', 'reading', 'story', 'stories', 'book',
    'leer', 'cuento',
    'lire', 'histoire',
    'vorlesen', 'geschichte',
  ]),
  // 8. nap
  _TaskIconRule(Icons.hotel_rounded, const [
    'nap',
    'siesta',
    'sieste',
    'mittagsschlaf',
  ]),
  // 9. night
  _TaskIconRule(Icons.nights_stay_rounded, const [
    'night', 'wake',
    'noche', 'despertar',
    'nuit', 'reveil',
    'nacht', 'aufwachen',
  ]),
  // 10. bedtime
  _TaskIconRule(Icons.bedtime_rounded, const [
    'bedtime', 'bed', 'sleep',
    'dormir', 'cama', 'acostar',
    'coucher', 'lit',
    'bett', 'schlafen',
  ]),
  // 11. bath
  _TaskIconRule(Icons.bathtub_rounded, const [
    'bath', 'bathe', 'bathing', 'shower',
    'bano', 'ducha',
    'bain', 'douche',
    'bad', 'baden', 'dusche',
  ]),
  // 12. diaper
  _TaskIconRule(Icons.baby_changing_station_rounded, const [
    'diaper', 'nappy',
    'panal',
    'couche',
    'windel',
  ]),
  // 13. breakfast
  _TaskIconRule(Icons.free_breakfast_rounded, const [
    'breakfast',
    'desayuno',
    'petit-dejeuner', 'petit dejeuner',
    'fruhstuck',
  ]),
  // 14. lunch
  _TaskIconRule(Icons.lunch_dining_rounded, const [
    'lunch',
    'almuerzo', 'comida',
    'dejeuner',
    'mittagessen',
  ]),
  // 15. dinner
  _TaskIconRule(Icons.dinner_dining_rounded, const [
    'dinner', 'supper',
    'cena',
    'diner',
    'abendessen',
  ]),
  // 16. cook
  _TaskIconRule(Icons.soup_kitchen_rounded, const [
    'cook', 'cooking', 'meal',
    'cocinar',
    'cuisiner', 'repas',
    'kochen', 'essen',
  ]),
  // 17. dishes
  _TaskIconRule(Icons.soap_rounded, const [
    'dishes', 'kitchen',
    'platos', 'cocina', 'fregar',
    'vaisselle', 'cuisine',
    'geschirr', 'kuche', 'abwasch',
  ]),
  // 18. grocery
  _TaskIconRule(Icons.shopping_cart_rounded, const [
    'grocery', 'groceries', 'shopping',
    'compra', 'supermercado',
    'courses', 'supermarche',
    'einkauf', 'einkaufen',
  ]),
  // 19. laundry
  _TaskIconRule(Icons.local_laundry_service_rounded, const [
    'laundry', 'washing',
    'ropa', 'colada', 'lavadora',
    'lessive', 'linge',
    'wasche', 'waschen',
  ]),
  // 20. iron
  _TaskIconRule(Icons.iron_rounded, const [
    'iron', 'ironing',
    'planchar',
    'repasser',
    'bugeln',
  ]),
  // 21. trash
  _TaskIconRule(Icons.recycling_rounded, const [
    'trash', 'garbage', 'rubbish', 'recycling',
    'basura', 'reciclar',
    'poubelle', 'dechets',
    'mull', 'abfall',
  ]),
  // 22. clean
  _TaskIconRule(Icons.cleaning_services_rounded, const [
    'clean', 'cleaning', 'tidy', 'tidying', 'vacuum',
    'limpiar', 'limpieza', 'ordenar',
    'menage', 'nettoyer', 'ranger',
    'putzen', 'sauber', 'aufraumen',
  ]),
  // 23. garden
  _TaskIconRule(Icons.yard_rounded, const [
    'garden', 'yard',
    'jardin',
    'garten',
  ]),
  // 24. walk
  _TaskIconRule(Icons.directions_walk_rounded, const [
    'walk', 'walking',
    'paseo', 'pasear', 'caminar',
    'promenade', 'marche',
    'spaziergang', 'spazieren',
  ]),
  // 25. park
  _TaskIconRule(Icons.park_rounded, const [
    'park', 'outdoor', 'play', 'playing', 'playground',
    'parque', 'jugar', 'aire libre',
    'parc', 'jouer', 'dehors',
    'spielplatz', 'spielen', 'draussen',
  ]),
  // 26. gym
  _TaskIconRule(Icons.fitness_center_rounded, const [
    'gym', 'trainer', 'workout', 'sport', 'exercise',
    'gimnasio', 'entrenador', 'entrenar', 'deporte',
    'salle de sport', 'entrainement',
    'training', 'fitness',
  ]),
  // 27. drive
  _TaskIconRule(Icons.directions_car_rounded, const [
    'drive', 'driving', 'car', 'ride',
    'conducir', 'coche', 'llevar',
    'conduire', 'voiture',
    'fahren', 'auto',
  ]),
  // 28. morning
  _TaskIconRule(Icons.wb_sunny_rounded, const [
    'morning',
    'manana',
    'matin',
    'morgen',
  ]),
  // 29. baby
  _TaskIconRule(Icons.child_care_rounded, const [
    'baby', 'child', 'kids',
    'bebe', 'nino', 'ninos',
    'enfant',
    'kind', 'kinder',
  ]),
];

/// Returns a distinct [IconData] for an activity [title] based on keyword rules.
///
/// Matches keywords at word starts (`\b` + keyword). Returns `null` if no rule matches.
IconData? taskIconFor(String? title) {
  if (title == null || title.trim().isEmpty) return null;
  final normalized = _stripAccents(title.toLowerCase());
  for (final rule in _rules) {
    if (rule.regex.hasMatch(normalized)) {
      return rule.icon;
    }
  }
  return null;
}
