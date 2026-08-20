part of 'render_scene_viewport_widget.dart';

class _InlineLevelElevationField extends StatefulWidget {
  const _InlineLevelElevationField({
    super.key,
    required this.level,
    required this.onSubmitted,
  });

  final RenderSceneLevel level;
  final Future<void> Function(RenderSceneLevel level, String value)?
      onSubmitted;

  @override
  State<_InlineLevelElevationField> createState() =>
      _InlineLevelElevationFieldState();
}

class _InlineLevelElevationFieldState
    extends State<_InlineLevelElevationField> {
  late final TextEditingController _controller;
  bool _isCommitting = false;

  @override
  void initState() {
    super.initState();
    _controller = TextEditingController(
      text: widget.level.elevationMeters.toStringAsFixed(2),
    );
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  void didUpdateWidget(covariant _InlineLevelElevationField oldWidget) {
    super.didUpdateWidget(oldWidget);
    if ((oldWidget.level.elevationMeters - widget.level.elevationMeters).abs() >
        1e-6) {
      _controller.text = widget.level.elevationMeters.toStringAsFixed(2);
    }
  }

  Future<void> _commit() async {
    if (_isCommitting) {
      return;
    }
    final value = _controller.text.trim();
    if (value.isEmpty || double.tryParse(value) == null) {
      return;
    }
    setState(() => _isCommitting = true);
    try {
      await widget.onSubmitted?.call(widget.level, value);
      if (mounted) {
        FocusScope.of(context).unfocus();
      }
    } finally {
      if (mounted) {
        setState(() => _isCommitting = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 124,
      child: TextField(
        controller: _controller,
        autofocus: true,
        keyboardType:
            const TextInputType.numberWithOptions(decimal: true, signed: true),
        textInputAction: TextInputAction.done,
        onTap: () => _controller.selection = TextSelection(
          baseOffset: 0,
          extentOffset: _controller.text.length,
        ),
        onSubmitted: (_) => _commit(),
        onEditingComplete: _commit,
        decoration: InputDecoration(
          isDense: true,
          suffixText: 'm',
          suffixIcon: IconButton(
            tooltip: 'Apply elevation',
            onPressed: _isCommitting ? null : _commit,
            icon: _isCommitting
                ? const SizedBox(
                    width: 16,
                    height: 16,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.check),
          ),
          filled: true,
          fillColor: const Color(0xFFFFFFFF),
          border: const OutlineInputBorder(),
        ),
      ),
    );
  }
}

class _ViewportStatsCard extends StatelessWidget {
  const _ViewportStatsCard({
    required this.scene,
    required this.native,
  });

  final RenderScene scene;
  final bool native;

  @override
  Widget build(BuildContext context) {
    return Card(
      color: Colors.white.withValues(alpha: 0.90),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: DefaultTextStyle(
          style: Theme.of(context).textTheme.bodySmall ?? const TextStyle(),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              Text(
                  native ? 'Renderer: Filament' : 'Renderer: Flutter fallback'),
              Text('Objects: ${scene.objectCount}'),
              Text('Vertices: ${scene.vertexCount}'),
              Text('Indices: ${scene.indexCount}'),
              Text('Triangles: ${scene.triangleCount}'),
              Text(
                'Bounds: ${scene.bounds.width.toStringAsFixed(2)} × '
                '${scene.bounds.depth.toStringAsFixed(2)} × '
                '${scene.bounds.height.toStringAsFixed(2)} m',
              ),
            ],
          ),
        ),
      ),
    );
  }
}
