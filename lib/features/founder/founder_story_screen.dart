import 'package:flutter/material.dart';
import '../../core/theme/app_theme.dart';
import '../../widgets/glass_card.dart';

class FounderStoryScreen extends StatelessWidget {
  const FounderStoryScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppTheme.background,
      body: SafeArea(
        child: CustomScrollView(
          slivers: [
            SliverAppBar(
              backgroundColor: Colors.transparent,
              elevation: 0,
              leading: IconButton(
                icon: const Icon(Icons.arrow_back),
                onPressed: () => Navigator.pop(context),
              ),
              title: const Text('История создания'),
              centerTitle: true,
            ),
            SliverPadding(
              padding: const EdgeInsets.all(16),
              sliver: SliverToBoxAdapter(
                child: GlassCard(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Center(
                        child: Container(
                          width: 120,
                          height: 120,
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            border: Border.all(color: AppTheme.accentOrange, width: 3),
                            boxShadow: [
                              BoxShadow(
                                color: AppTheme.accentOrange.withOpacity(0.3),
                                blurRadius: 30,
                              ),
                            ],
                          ),
                          child: const Center(
                            child: Text('W', style: TextStyle(fontSize: 48, fontWeight: FontWeight.bold)),
                          ),
                        ),
                      ),
                      const SizedBox(height: 24),
                      const Text(
                        'Эту систему создал Байдин Владислав Евгеньевич, выступающий под псевдонимом Wesi, именно в его честь названа данная система.',
                        style: TextStyle(fontSize: 16, height: 1.6),
                      ),
                      const SizedBox(height: 16),
                      const Text(
                        'Влад родился в городе Коряжма 9 июля 2004 года, но всю молодость прожил в поселке городского типа Урдома в Архангельской области, именно там началась история создания личного бренда Wesi и личностного становления Владислава.',
                        style: TextStyle(fontSize: 16, height: 1.6),
                      ),
                      const SizedBox(height: 16),
                      const Text(
                        'С ранних лет Влад понял, что способен на многое, в 14 лет начал делать первые шаги к своему великому будущему, в 15 лет начал заниматься битмейкингом и активно заниматься саморазвитием.',
                        style: TextStyle(fontSize: 16, height: 1.6),
                      ),
                      const SizedBox(height: 16),
                      const Text(
                        'К 20 годам набрался опыта в нише и в 21 год основал компанию Wesi Inc.',
                        style: TextStyle(fontSize: 16, height: 1.6),
                      ),
                      const SizedBox(height: 16),
                      const Text(
                        'В 2026 году в день его рождения родилась система Wesi OS, которая помогает компании сворачивать горы и менять этот мир!',
                        style: TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.bold,
                          color: AppTheme.accentOrange,
                          height: 1.6,
                        ),
                      ),
                      const SizedBox(height: 32),
                      const Center(
                        child: Text(
                          '«Система, которая помогает менять мир!»',
                          style: TextStyle(
                            fontSize: 14,
                            fontStyle: FontStyle.italic,
                            color: AppTheme.textSecondary,
                          ),
                          textAlign: TextAlign.center,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
