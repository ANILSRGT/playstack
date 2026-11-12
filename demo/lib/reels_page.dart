import 'package:flutter/material.dart';
import 'package:reelkit/reelkit.dart';
import 'package:reelkit_demo/catalog.dart';

class ReelsPage extends StatefulWidget {
  const ReelsPage({super.key});

  @override
  State<ReelsPage> createState() => _ReelsPageState();
}

class _ReelsPageState extends State<ReelsPage> {
  final feedViewCtrl = ReelFeedViewController();

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: ReelFeedView<DemoVideo>(
        items: demoCatalog,
        onLoadMore: () => Future.value(demoCatalog),
        source: (item) => item.source,
        posterUrl: (item) => item.poster,
        controller: feedViewCtrl,
        transition: ReelFeedTransition.stack,
        controlsBuilder: (_, page) {
          return SizedBox();
        },
      ),
    );
  }
}
