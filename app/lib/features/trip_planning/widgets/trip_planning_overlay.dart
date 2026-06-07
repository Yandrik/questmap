import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:watch_it/watch_it.dart';

import '../manager/trip_agent_manager.dart';
import '../model/trip_planning_session.dart';

class TripPlanningOverlay extends WatchingStatefulWidget {
  const TripPlanningOverlay({super.key});

  @override
  State<TripPlanningOverlay> createState() => _TripPlanningOverlayState();
}

class _TripPlanningOverlayState extends State<TripPlanningOverlay>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;
  late final List<String> _messages;
  Timer? _timer;
  int _messageIndex = 0;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 2),
    )..repeat(reverse: true);
    _messages = _shuffledMessages();
    _timer = Timer.periodic(const Duration(seconds: 4), (_) {
      if (!mounted) return;
      setState(() => _messageIndex = (_messageIndex + 1) % _messages.length);
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final agent = watchIt<TripAgentManager>();
    final question = agent.question;
    final theme = Theme.of(context);

    return ColoredBox(
      color: Colors.black.withValues(alpha: 0.58),
      child: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 560),
              child: Material(
                borderRadius: BorderRadius.circular(12),
                color: theme.colorScheme.surface,
                child: Padding(
                  padding: const EdgeInsets.all(18),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          AnimatedBuilder(
                            animation: _controller,
                            builder: (context, child) => Transform.scale(
                              scale: 1 + _controller.value * 0.12,
                              child: child,
                            ),
                            child: Icon(
                              Icons.auto_awesome,
                              color: theme.colorScheme.primary,
                              size: 34,
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Text(
                              'Planning your trip',
                              style: theme.textTheme.titleLarge?.copyWith(
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                          ),
                          IconButton(
                            tooltip: 'Cancel planning',
                            onPressed: () => _confirmCancel(context),
                            icon: const Icon(Icons.close),
                          ),
                        ],
                      ),
                      const SizedBox(height: 16),
                      LinearProgressIndicator(
                        minHeight: 6,
                        borderRadius: BorderRadius.circular(999),
                      ),
                      const SizedBox(height: 16),
                      Text(
                        agent.statusMessage ?? _messages[_messageIndex],
                        style: theme.textTheme.bodyLarge,
                      ),
                      Text(
                        _messages[_messageIndex],
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: theme.colorScheme.onSurfaceVariant,
                        ),
                      ),
                      if (agent.partialPlan != null) ...[
                        const SizedBox(height: 14),
                        Text(
                          'Progress: ${agent.partialPlan!.items.length} steps shaped',
                          style: theme.textTheme.labelLarge,
                        ),
                      ],
                      if (question != null) ...[
                        const SizedBox(height: 18),
                        _QuestionCard(question: question),
                      ],
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Future<void> _confirmCancel(BuildContext context) async {
    final cancel = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Cancel planning?'),
        content: const Text('The current agent run will be stopped.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Keep waiting'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('Cancel'),
          ),
        ],
      ),
    );
    if (cancel == true) {
      await di<TripAgentManager>().cancelPlanning();
    }
  }

  static List<String> _shuffledMessages() {
    final messages = [
      'Considering trip plans...',
      'Finding awesome views...',
      'Looking for the best spots...',
      'Checking transport options...',
      'Balancing walking time...',
      'Scanning food choices...',
      'Finding relaxed detours...',
      'Checking nearby shops...',
      'Looking for memorable stops...',
      'Estimating travel legs...',
      'Comparing neighborhoods...',
      'Reading your preferences...',
      'Finding places worth lingering...',
      'Avoiding awkward backtracking...',
      'Checking public transport timing...',
      'Looking for better alternatives...',
      'Pairing activities with routes...',
      'Finding a good rhythm...',
      'Checking arrival constraints...',
      'Finding places near your route...',
      'Tuning the schedule...',
      'Exploring walkable areas...',
      'Looking for local highlights...',
      'Picking useful transfer points...',
      'Checking if the plan breathes...',
      'Finding a good first stop...',
      'Testing route order...',
      'Looking for practical options...',
      'Comparing scenic paths...',
      'Finding good breaks...',
      'Checking opening-time assumptions...',
      'Shaping the itinerary...',
      'Matching places to your notes...',
      'Finding backup options...',
      'Checking travel-time budgets...',
      'Looking for a clean finish...',
      'Comparing route candidates...',
      'Finding comfortable transitions...',
      'Checking if this feels doable...',
      'Picking standout places...',
      'Reviewing exact-location stops...',
      'Combining modes sensibly...',
      'Looking for low-friction moves...',
      'Finding nearby clusters...',
      'Checking the end location...',
      'Choosing route geometry...',
      'Drafting explanations...',
      'Checking for boring gaps...',
      'Building the final sequence...',
      'Polishing the trip plan...',
    ];
    final random = math.Random(42);
    for (var i = messages.length - 1; i > 0; i--) {
      final j = random.nextInt(i + 1);
      final item = messages[i];
      messages[i] = messages[j];
      messages[j] = item;
    }
    return messages;
  }
}

class _QuestionCard extends StatefulWidget {
  const _QuestionCard({required this.question});

  final TripPlanningQuestion question;

  @override
  State<_QuestionCard> createState() => _QuestionCardState();
}

class _QuestionCardState extends State<_QuestionCard> {
  final _controller = TextEditingController();

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final question = widget.question;
    final theme = Theme.of(context);

    return DecoratedBox(
      decoration: BoxDecoration(
        color: theme.colorScheme.primaryContainer.withValues(alpha: 0.35),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              question.prompt,
              style: theme.textTheme.titleSmall?.copyWith(
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(height: 12),
            switch (question.kind) {
              TripPlanningQuestionKind.yesNo => _YesNoAnswer(),
              TripPlanningQuestionKind.number => _TextAnswer(
                controller: _controller,
                keyboardType: TextInputType.number,
                label: question.unit ?? 'Number',
                parser: (value) => num.tryParse(value),
              ),
              TripPlanningQuestionKind.text => _TextAnswer(
                controller: _controller,
                keyboardType: TextInputType.text,
                label: 'Answer',
                parser: (value) => value.trim(),
              ),
              TripPlanningQuestionKind.selection => _SelectionAnswer(
                question: question,
              ),
              TripPlanningQuestionKind.routeChoice => _SelectionAnswer(
                question: question,
              ),
            },
          ],
        ),
      ),
    );
  }
}

class _YesNoAnswer extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Expanded(
          child: FilledButton(
            onPressed: () => di<TripAgentManager>().answerQuestion(true),
            child: const Text('Yes'),
          ),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: OutlinedButton(
            onPressed: () => di<TripAgentManager>().answerQuestion(false),
            child: const Text('No'),
          ),
        ),
      ],
    );
  }
}

class _TextAnswer extends StatelessWidget {
  const _TextAnswer({
    required this.controller,
    required this.keyboardType,
    required this.label,
    required this.parser,
  });

  final TextEditingController controller;
  final TextInputType keyboardType;
  final String label;
  final Object? Function(String value) parser;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Expanded(
          child: TextField(
            controller: controller,
            keyboardType: keyboardType,
            decoration: InputDecoration(
              labelText: label,
              border: const OutlineInputBorder(),
            ),
          ),
        ),
        const SizedBox(width: 8),
        FilledButton(
          onPressed: () =>
              di<TripAgentManager>().answerQuestion(parser(controller.text)),
          child: const Text('Send'),
        ),
      ],
    );
  }
}

class _SelectionAnswer extends StatelessWidget {
  const _SelectionAnswer({required this.question});

  final TripPlanningQuestion question;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        for (final option in question.options)
          Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: ListTile(
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(8),
              ),
              tileColor: Theme.of(context).colorScheme.surface,
              leading: option.imageUrl == null
                  ? const Icon(Icons.place)
                  : ClipRRect(
                      borderRadius: BorderRadius.circular(6),
                      child: Image.network(
                        option.imageUrl!,
                        width: 48,
                        height: 48,
                        fit: BoxFit.cover,
                      ),
                    ),
              title: Text(option.title),
              subtitle: option.description == null
                  ? null
                  : Text(option.description!),
              onTap: () => di<TripAgentManager>().answerQuestion(option.id),
            ),
          ),
      ],
    );
  }
}
