const List<Map<String, dynamic>> seedChallengesData = [
  {
    'id': 'seed_01',
    'title': 'Python: Listas',
    'question': '¿Cómo se añade un elemento al final de una lista?',
    'code_snippet': 'lista.___(item)',
    'correct_answer': 'append',
    'technology': 'Python',
    'level': 'BEGINNER',

  },
  {
    'id': 'seed_02',
    'title': 'JS: Asincronía',
    'question': '¿Qué palabra se usa para esperar una promesa?',
    'code_snippet': 'async function x() { ___ task(); }',
    'correct_answer': 'await',
    'technology': 'JavaScript',
    'level': 'INTERMEDIATE',

  },
  {
    'id': 'seed_03',
    'title': 'SQL: Filtros',
    'question': '¿Qué cláusula se usa para filtrar resultados?',
    'code_snippet': 'SELECT * FROM users ___ id = 1;',
    'correct_answer': 'WHERE',
    'technology': 'SQL',
    'level': 'BEGINNER',

  },
  {
    'id': 'seed_04',
    'title': 'Dart: Inferencia',
    'question': '¿Qué palabra se usa para inferencia de tipo?',
    'code_snippet': '___ name = "Dev";',
    'correct_answer': 'var',
    'technology': 'Dart',
    'level': 'BEGINNER',

  },
  {
    'id': 'seed_05',
    'title': 'Flutter: Widgets',
    'question': '¿Cuál es el widget base de una app Material?',
    'code_snippet':
        'class App extends StatelessWidget {\n  @override\n  Widget build(BuildContext context) {\n    return ___();\n  }\n}',
    'correct_answer': 'MaterialApp',
    'technology': 'Flutter',
    'level': 'BEGINNER',

  },
  {
    'id': 'seed_06',
    'title': 'CSS: Flexbox',
    'question': 'Propiedad para alinear en el eje principal:',
    'code_snippet': 'display: flex;\n___: center;',
    'correct_answer': 'justify-content',
    'technology': 'CSS',
    'level': 'INTERMEDIATE',

  },
  {
    'id': 'seed_11',
    'title': 'Docker: Imagen',
    'question': 'Completa el comando:',
    'code_snippet': 'docker ___ -t mi-app .',
    'correct_answer': 'build',
    'technology': 'Docker',
    'level': 'INTERMEDIATE',

  },
  {
    'id': 'seed_12',
    'title': 'Git: Ramas',
    'question': 'Comando para cambiar de rama:',
    'code_snippet': 'git ___ nueva-rama',
    'correct_answer': 'checkout',
    'technology': 'Git',
    'level': 'BEGINNER',

  },
  {
    'id': 'seed_14',
    'title': 'TypeScript: Tipos',
    'question': 'Tipo para permitir cualquier valor:',
    'code_snippet': 'let x: ___ = 10;',
    'correct_answer': 'any',
    'technology': 'TypeScript',
    'level': 'INTERMEDIATE',

  },
  {
    'id': 'seed_16',
    'title': 'Java: Impresión',
    'question': 'Completa la función:',
    'code_snippet': 'System.out.___("Hola");',
    'correct_answer': 'println',
    'technology': 'Java',
    'level': 'BEGINNER',

  },
  {
    'id': 'seed_17',
    'title': 'Java: Herencia',
    'question': 'Palabra clave para heredar:',
    'code_snippet': 'class B ___ A {}',
    'correct_answer': 'extends',
    'technology': 'Java',
    'level': 'BEGINNER',

  },
  {
    'id': 'seed_18',
    'title': 'Rust: Mutabilidad',
    'question': 'Declara variable mutable:',
    'code_snippet': 'let ___ x = 5;',
    'correct_answer': 'mut',
    'technology': 'Rust',
    'level': 'ADVANCED',

  },
  {
    'id': 'seed_20',
    'title': 'Linux: Permisos',
    'question': 'Completa el comando:',
    'code_snippet': '___ 755 script.sh',
    'correct_answer': 'chmod',
    'technology': 'Linux',
    'level': 'ADVANCED',

  },
  {
    'id': 'seed_21',
    'title': 'Python: Longitud',
    'question': '¿Función para obtener la longitud de una lista?',
    'code_snippet': 'len(___)',
    'correct_answer': 'lista',
    'technology': 'Python',
    'level': 'BEGINNER',

  },
  {
    'id': 'seed_22',
    'title': 'JavaScript: Arrays',
    'question': 'Método para añadir al final de un array:',
    'code_snippet': 'arr.___(item);',
    'correct_answer': 'push',
    'technology': 'JavaScript',
    'level': 'BEGINNER',

  },
  {
    'id': 'seed_23',
    'title': 'SQL: Orden',
    'question': 'Cláusula para ordenar resultados:',
    'code_snippet': 'SELECT * FROM users ___ name ASC;',
    'correct_answer': 'ORDER BY',
    'technology': 'SQL',
    'level': 'INTERMEDIATE',

  },
  {
    'id': 'seed_24',
    'title': 'Dart: Constantes',
    'question': 'Palabra para declarar una constante en tiempo de compilación:',
    'code_snippet': '___ pi = 3.14;',
    'correct_answer': 'const',
    'technology': 'Dart',
    'level': 'INTERMEDIATE',

  },
  {
    'id': 'seed_25',
    'title': 'Flutter: Texto',
    'question': 'Widget para mostrar texto:',
    'code_snippet': '___("Hola")',
    'correct_answer': 'Text',
    'technology': 'Flutter',
    'level': 'BEGINNER',

  },
  {
    'id': 'seed_26',
    'title': 'CSS: Color',
    'question': 'Propiedad para cambiar el color del texto:',
    'code_snippet': '___: red;',
    'correct_answer': 'color',
    'technology': 'CSS',
    'level': 'BEGINNER',

  },
  {
    'id': 'seed_27',
    'title': 'Docker: Contenedores',
    'question': 'Comando para listar contenedores en ejecución:',
    'code_snippet': 'docker ___',
    'correct_answer': 'ps',
    'technology': 'Docker',
    'level': 'INTERMEDIATE',

  },
  {
    'id': 'seed_28',
    'title': 'Git: Estado',
    'question': 'Comando para ver cambios en el repositorio:',
    'code_snippet': 'git ___',
    'correct_answer': 'status',
    'technology': 'Git',
    'level': 'BEGINNER',

  },
  {
    'id': 'seed_29',
    'title': 'TypeScript: Interfaces',
    'question': 'Palabra clave para definir una interfaz:',
    'code_snippet': '___ User { name: string; }',
    'correct_answer': 'interface',
    'technology': 'TypeScript',
    'level': 'INTERMEDIATE',

  },
  {
    'id': 'seed_30',
    'title': 'Linux: Directorios',
    'question': 'Comando para listar archivos:',
    'code_snippet': '___ -la',
    'correct_answer': 'ls',
    'technology': 'Linux',
    'level': 'BEGINNER',

  },
];
