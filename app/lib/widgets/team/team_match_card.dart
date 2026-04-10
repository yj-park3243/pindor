import 'package:flutter/material.dart';
import 'package:cached_network_image/cached_network_image.dart';
import '../../config/theme.dart';
import '../../models/team.dart';

/// 팀 매칭 카드 위젯
class TeamMatchCard extends StatelessWidget {
  final TeamMatch match;
  final String myTeamId;
  final VoidCallback? onTap;

  const TeamMatchCard({
    super.key,
    required this.match,
    required this.myTeamId,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final isHome = match.homeTeamId == myTeamId;
    final myTeam = isHome ? match.homeTeam : match.awayTeam;
    final opponentTeam = isHome ? match.awayTeam : match.homeTeam;
    final myScore = isHome ? match.homeScore : match.awayScore;
    final oppScore = isHome ? match.awayScore : match.homeScore;

    return Card(
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(16),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            children: [
              // 상태 + 날짜
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  _StatusChip(status: match.status),
                  if (match.scheduledDate != null)
                    Text(
                      '${match.scheduledDate} ${match.scheduledTime ?? ''}',
                      style: const TextStyle(
                        fontSize: 12,
                        color: AppTheme.textSecondary,
                      ),
                    ),
                ],
              ),
              const SizedBox(height: 16),

              // 양 팀 vs 레이아웃
              Row(
                children: [
                  // 내 팀
                  Expanded(
                    child: _TeamInfo(
                      name: myTeam?.name ?? '내 팀',
                      logoUrl: myTeam?.logoUrl,
                      isLeft: true,
                    ),
                  ),

                  // 스코어 / VS
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 12),
                    child: match.isCompleted
                        ? Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Text(
                                '${myScore ?? 0}',
                                style: TextStyle(
                                  fontSize: 28,
                                  fontWeight: FontWeight.w800,
                                  color: _getScoreColor(myScore, oppScore),
                                ),
                              ),
                              const Padding(
                                padding: EdgeInsets.symmetric(horizontal: 8),
                                child: Text(
                                  ':',
                                  style: TextStyle(
                                    fontSize: 24,
                                    fontWeight: FontWeight.w700,
                                    color: AppTheme.textSecondary,
                                  ),
                                ),
                              ),
                              Text(
                                '${oppScore ?? 0}',
                                style: const TextStyle(
                                  fontSize: 28,
                                  fontWeight: FontWeight.w800,
                                  color: AppTheme.textSecondary,
                                ),
                              ),
                            ],
                          )
                        : const Text(
                            'VS',
                            style: TextStyle(
                              fontSize: 20,
                              fontWeight: FontWeight.w800,
                              color: AppTheme.textSecondary,
                            ),
                          ),
                  ),

                  // 상대 팀
                  Expanded(
                    child: _TeamInfo(
                      name: opponentTeam?.name ?? '상대 팀',
                      logoUrl: opponentTeam?.logoUrl,
                      isLeft: false,
                    ),
                  ),
                ],
              ),

              // 장소
              if (match.venueName != null) ...[
                const SizedBox(height: 12),
                const Divider(height: 1),
                const SizedBox(height: 8),
                Row(
                  children: [
                    const Icon(
                      Icons.location_on_outlined,
                      size: 14,
                      color: AppTheme.textSecondary,
                    ),
                    const SizedBox(width: 4),
                    Text(
                      match.venueName!,
                      style: const TextStyle(
                        fontSize: 12,
                        color: AppTheme.textSecondary,
                      ),
                    ),
                  ],
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }

  Color _getScoreColor(int? myScore, int? oppScore) {
    if (myScore == null || oppScore == null) return AppTheme.textSecondary;
    if (myScore > oppScore) return AppTheme.secondaryColor;
    if (myScore < oppScore) return AppTheme.errorColor;
    return AppTheme.textSecondary;
  }
}

class _TeamInfo extends StatelessWidget {
  final String name;
  final String? logoUrl;
  final bool isLeft;

  const _TeamInfo({
    required this.name,
    this.logoUrl,
    required this.isLeft,
  });

  @override
  Widget build(BuildContext context) {
    final initial = name.isNotEmpty ? name[0].toUpperCase() : 'T';

    final logoWidget = logoUrl != null
        ? ClipRRect(
            borderRadius: BorderRadius.circular(10),
            child: CachedNetworkImage(
              imageUrl: logoUrl!,
              width: 44,
              height: 44,
              fit: BoxFit.cover,
              memCacheWidth: 88,
              memCacheHeight: 88,
              errorWidget: (c, u, e) => _buildFallback(initial),
            ),
          )
        : _buildFallback(initial);

    return Column(
      crossAxisAlignment:
          isLeft ? CrossAxisAlignment.start : CrossAxisAlignment.end,
      children: [
        logoWidget,
        const SizedBox(height: 6),
        Text(
          name,
          style: const TextStyle(
            fontSize: 13,
            fontWeight: FontWeight.w600,
          ),
          textAlign: isLeft ? TextAlign.left : TextAlign.right,
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
        ),
      ],
    );
  }

  Widget _buildFallback(String initial) {
    return Container(
      width: 44,
      height: 44,
      decoration: BoxDecoration(
        color: AppTheme.primaryColor.withOpacity(0.1),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Center(
        child: Text(
          initial,
          style: const TextStyle(
            fontSize: 18,
            fontWeight: FontWeight.w700,
            color: AppTheme.primaryColor,
          ),
        ),
      ),
    );
  }
}

class _StatusChip extends StatelessWidget {
  final String status;

  const _StatusChip({required this.status});

  @override
  Widget build(BuildContext context) {
    Color color;
    String label;

    switch (status) {
      case 'PENDING':
        color = AppTheme.warningColor;
        label = '요청 중';
        break;
      case 'ACCEPTED':
        color = AppTheme.primaryColor;
        label = '수락됨';
        break;
      case 'CONFIRMED':
        color = AppTheme.secondaryColor;
        label = '경기 확정';
        break;
      case 'COMPLETED':
        color = AppTheme.textSecondary;
        label = '완료';
        break;
      case 'CANCELLED':
        color = AppTheme.errorColor;
        label = '취소됨';
        break;
      default:
        color = AppTheme.textSecondary;
        label = status;
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: color.withOpacity(0.1),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: color.withOpacity(0.3)),
      ),
      child: Text(
        label,
        style: TextStyle(
          fontSize: 11,
          fontWeight: FontWeight.w600,
          color: color,
        ),
      ),
    );
  }
}
