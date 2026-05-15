import 'dart:io' show Platform;

import 'package:flutter/foundation.dart' show kDebugMode;
import 'package:flutter/material.dart';
import 'package:google_mobile_ads/google_mobile_ads.dart';

import '../../config/theme.dart';
import '../../core/version/version_check_service.dart';

class AdUnitIds {
  static String get nativeAdUnitId {
    // 디버그 빌드(에뮬레이터/시뮬레이터 개발 환경)에선 Google 공식 테스트 ID 사용.
    // 실 광고 ID로 에뮬레이터에 광고 요청하면 송출 안 됨 + 계정 제재 위험.
    if (kDebugMode) {
      if (Platform.isAndroid) {
        return 'ca-app-pub-3940256099942544/2247696110';
      }
      return 'ca-app-pub-3940256099942544/3986624511';
    }
    if (Platform.isAndroid) {
      return 'ca-app-pub-5100715769469045/8485165724';
    }
    return 'ca-app-pub-5100715769469045/5254321554';
  }
}

class NativeAdCard extends StatefulWidget {
  final bool highlightAdLabel;
  final EdgeInsetsGeometry padding;

  const NativeAdCard({
    super.key,
    this.highlightAdLabel = false,
    this.padding = const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
  });

  @override
  State<NativeAdCard> createState() => _NativeAdCardState();
}

class _NativeAdCardState extends State<NativeAdCard> {
  NativeAd? _ad;
  bool _loaded = false;
  bool _failed = false;

  @override
  void initState() {
    super.initState();
    // 서버 원격 토글: showAd=false면 광고 로드 자체를 안 함
    if (VersionCheckService.showAd) {
      _loadAd();
    }
  }

  void _loadAd() {
    _ad = NativeAd(
      adUnitId: AdUnitIds.nativeAdUnitId,
      request: const AdRequest(),
      listener: NativeAdListener(
        onAdLoaded: (_) {
          if (mounted) setState(() => _loaded = true);
        },
        onAdFailedToLoad: (ad, error) {
          ad.dispose();
          if (mounted) setState(() => _failed = true);
        },
      ),
      nativeTemplateStyle: NativeTemplateStyle(
        templateType: TemplateType.medium,
        mainBackgroundColor: const Color(0xFF141414),
        cornerRadius: 12,
        callToActionTextStyle: NativeTemplateTextStyle(
          textColor: Colors.white,
          backgroundColor: AppTheme.primaryColor,
          style: NativeTemplateFontStyle.bold,
          size: 14,
        ),
        primaryTextStyle: NativeTemplateTextStyle(
          textColor: Colors.white,
          backgroundColor: const Color(0xFF141414),
          style: NativeTemplateFontStyle.bold,
          size: 15,
        ),
        secondaryTextStyle: NativeTemplateTextStyle(
          textColor: AppTheme.textSecondary,
          backgroundColor: const Color(0xFF141414),
          style: NativeTemplateFontStyle.normal,
          size: 13,
        ),
        tertiaryTextStyle: NativeTemplateTextStyle(
          textColor: AppTheme.textDisabled,
          backgroundColor: const Color(0xFF141414),
          style: NativeTemplateFontStyle.normal,
          size: 12,
        ),
      ),
    )..load();
  }

  @override
  void dispose() {
    _ad?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    // 원격 토글 OFF면 카드 자체를 그리지 않음
    if (!VersionCheckService.showAd) return const SizedBox.shrink();
    if (_failed) return const SizedBox.shrink();
    if (!_loaded || _ad == null) {
      return Padding(
        padding: widget.padding,
        child: Container(
          height: 320,
          decoration: BoxDecoration(
            color: const Color(0xFF141414),
            borderRadius: BorderRadius.circular(12),
          ),
        ),
      );
    }

    final adView = ClipRRect(
      borderRadius: BorderRadius.circular(12),
      child: SizedBox(
        height: 320,
        child: AdWidget(ad: _ad!),
      ),
    );

    return Padding(
      padding: widget.padding,
      child: widget.highlightAdLabel
          ? Stack(
              children: [
                adView,
                Positioned(
                  top: 8,
                  right: 8,
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 8, vertical: 3),
                    decoration: BoxDecoration(
                      color: AppTheme.primaryColor,
                      borderRadius: BorderRadius.circular(6),
                    ),
                    child: const Text(
                      '광고',
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 11,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                ),
              ],
            )
          : adView,
    );
  }
}
