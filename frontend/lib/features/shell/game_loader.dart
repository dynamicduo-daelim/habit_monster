import 'package:flutter/material.dart';

import '../../core/api/api_exception.dart';
import '../../core/state/game_repository.dart';
import '../../core/state/game_state.dart';
import '../../core/theme/app_colors.dart';
import '../../core/widgets/pixel_widgets.dart';

/// 서버 모드에서 홈을 그리기 전에 내 데이터를 불러온다 (결정 D-40).
/// 게임 상태가 아직 비어 있으면([GameState.loaded]가 false) 불러오는 동안 로딩 화면, 실패하면 "다시 시도".
/// 서버 없이 쓰는 샘플 상태는 처음부터 불러온 것으로 치므로 바로 [child]를 그린다.
class GameLoader extends StatefulWidget {
  const GameLoader({super.key, required this.child});

  final Widget child;

  @override
  State<GameLoader> createState() => _GameLoaderState();
}

class _GameLoaderState extends State<GameLoader> {
  bool _loading = false;
  String? _error;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (!GameScope.read(context).loaded && !_loading && _error == null) _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      await GameRepositoryScope.of(context).load();
    } on ApiException catch (e) {
      if (mounted) setState(() => _error = e.message);
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (GameScope.of(context).loaded) return widget.child;
    return Scaffold(
      backgroundColor: AppColors.introSky,
      body: Center(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 32),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                _error ?? '몬스터들을 깨우는 중…',
                textAlign: TextAlign.center,
                style: const TextStyle(fontSize: 13, color: AppColors.text),
              ),
              const SizedBox(height: 18),
              if (_error == null)
                const SizedBox(
                  width: 22,
                  height: 22,
                  child: CircularProgressIndicator(strokeWidth: 3, color: AppColors.gold),
                )
              else
                SizedBox(width: 180, child: PixelButton(label: '다시 시도', onPressed: _load)),
            ],
          ),
        ),
      ),
    );
  }
}
