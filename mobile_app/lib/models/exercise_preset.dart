class RepInfo {
  final int repNumber;
  final double startTime;
  final double peakTime;
  final double endTime;
  final double concentricDuration;
  final double eccentricDuration;
  final double totalDuration;
  final double minAngle;
  final double maxAngle;
  final double rom;
  final bool isValid;
  final String feedback;

  const RepInfo({
    required this.repNumber,
    required this.startTime,
    required this.peakTime,
    required this.endTime,
    required this.concentricDuration,
    required this.eccentricDuration,
    required this.totalDuration,
    required this.minAngle,
    required this.maxAngle,
    required this.rom,
    required this.isValid,
    required this.feedback,
  });
}

class ExerciseConfig {
  final String name;
  final String displayName;
  final List<String> targetJoints;
  final double startThreshold;
  final double peakThreshold;
  final bool invert; // True se o pico for um ângulo menor (ex: agachamento/flexão)
  final String instructionStart;
  final String instructionDown;
  final String instructionUp;

  const ExerciseConfig({
    required this.name,
    required this.displayName,
    required this.targetJoints,
    required this.startThreshold,
    required this.peakThreshold,
    this.invert = true,
    required this.instructionStart,
    required this.instructionDown,
    required this.instructionUp,
  });
}

const Map<String, ExerciseConfig> exercisePresets = {
  'free': ExerciseConfig(
    name: 'free',
    displayName: 'Modo Livre (ROM Geral)',
    targetJoints: [],
    startThreshold: 0,
    peakThreshold: 0,
    instructionStart: 'Movimente-se livremente para medir amplitudes',
    instructionDown: '',
    instructionUp: '',
  ),
  'squat': ExerciseConfig(
    name: 'squat',
    displayName: 'Agachamento (Squat)',
    targetJoints: ['joelho_esq', 'joelho_dir'],
    startThreshold: 155,
    peakThreshold: 95,
    invert: true,
    instructionStart: 'Fique em pé para iniciar',
    instructionDown: 'Agache até os joelhos ficarem a 90°',
    instructionUp: 'Suba de volta estendendo as pernas',
  ),
  'curl': ExerciseConfig(
    name: 'curl',
    displayName: 'Rosca Bíceps (Arm Curl)',
    targetJoints: ['cotovelo_esq', 'cotovelo_dir'],
    startThreshold: 145,
    peakThreshold: 55,
    invert: true,
    instructionStart: 'Estenda os braços para iniciar',
    instructionDown: 'Flexione os cotovelos subindo o peso',
    instructionUp: 'Desça controladamente até estender',
  ),
  'chin_up': ExerciseConfig(
    name: 'chin_up',
    displayName: 'Barra / Puxada (Chin-up)',
    targetJoints: ['cotovelo_esq', 'cotovelo_dir'],
    startThreshold: 150,
    peakThreshold: 60,
    invert: true,
    instructionStart: 'Posicione-se suspenso na barra',
    instructionDown: 'Puxe o corpo até o queixo passar da barra',
    instructionUp: 'Desça de forma controlada',
  ),
};

