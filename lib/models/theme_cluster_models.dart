import 'entity/photo_entity.dart';

class ThemeDefinition {
	const ThemeDefinition({
		required this.id,
		required this.title,
		required this.subtitle,
		required this.prototypePrompts,
		required this.keywords,
		required this.minSimilarity,
	});

	final String id;
	final String title;
	final String subtitle;
	final List<String> prototypePrompts;
	final List<String> keywords;
	final double minSimilarity;
}

class ThemeCluster {
	const ThemeCluster({
		required this.definition,
		required this.subclusters,
	});

	final ThemeDefinition definition;
	final List<ThemeSubcluster> subclusters;

	int get totalPhotos =>
			subclusters.fold<int>(0, (sum, item) => sum + item.totalPhotos);

	List<PhotoEntity> get coverPhotos =>
			subclusters.expand((item) => item.coverPhotos).take(4).toList(growable: false);

	int get totalTimelineGroups =>
			subclusters.fold<int>(0, (sum, item) => sum + item.groups.length);

	ThemeSubcluster get primarySubcluster => subclusters.first;
}

class ThemeSubcluster {
	const ThemeSubcluster({
		required this.id,
		required this.title,
		required this.subtitle,
		required this.algorithm,
		required this.cohesion,
		required this.totalPhotos,
		required this.coverPhotos,
		required this.groups,
	});

	final String id;
	final String title;
	final String subtitle;
	final ThemeSubclusterAlgorithm algorithm;
	final ThemeSubclusterCohesion? cohesion;
	final int totalPhotos;
	final List<PhotoEntity> coverPhotos;
	final List<ThemeTimelineGroup> groups;

	ThemeSubcluster copyWith({
		String? id,
		String? title,
		String? subtitle,
		ThemeSubclusterAlgorithm? algorithm,
		ThemeSubclusterCohesion? cohesion,
		int? totalPhotos,
		List<PhotoEntity>? coverPhotos,
		List<ThemeTimelineGroup>? groups,
	}) {
		return ThemeSubcluster(
			id: id ?? this.id,
			title: title ?? this.title,
			subtitle: subtitle ?? this.subtitle,
			algorithm: algorithm ?? this.algorithm,
			cohesion: cohesion ?? this.cohesion,
			totalPhotos: totalPhotos ?? this.totalPhotos,
			coverPhotos: coverPhotos ?? this.coverPhotos,
			groups: groups ?? this.groups,
		);
	}
}

class ThemeSubclusterCohesion {
	const ThemeSubclusterCohesion({
		required this.meanDistance,
		required this.sampleCount,
	});

	final double meanDistance;
	final int sampleCount;

	String get levelLabel {
		if (meanDistance <= 0.08) {
			return '精选';
		}
		if (meanDistance <= 0.14) {
			return '中等';
		}
		return '松散';
	}

	String get summaryLabel => '$levelLabel · 均距 ${meanDistance.toStringAsFixed(3)}';

	String get detailLabel {
		if (meanDistance <= 0.08) {
			return '簇内非常紧密，适合折叠成精选簇';
		}
		if (meanDistance <= 0.14) {
			return '簇内有一定变化，适合保留分组浏览';
		}
		return '簇内跨度较大，更适合平铺展示';
	}
}

class ThemeSubclusterAlgorithm {
	const ThemeSubclusterAlgorithm({
		required this.currentLabel,
		required this.nextLabel,
	});

	final String currentLabel;
	final String nextLabel;
}

class ScoredThemePhoto {
	const ScoredThemePhoto({
		required this.photo,
		required this.score,
		required this.embedding,
	});

	final PhotoEntity photo;
	final double score;
	final List<double> embedding;

	ScoredThemePhoto copyWith({
		PhotoEntity? photo,
		double? score,
		List<double>? embedding,
	}) {
		return ScoredThemePhoto(
			photo: photo ?? this.photo,
			score: score ?? this.score,
			embedding: embedding ?? this.embedding,
		);
	}
}

class ThemeTimelineGroup {
	const ThemeTimelineGroup({
		required this.key,
		required this.title,
		required this.monthStart,
		required this.photos,
		required this.totalPhotos,
	});

	final String key;
	final String title;
	final DateTime monthStart;
	final List<PhotoEntity> photos;
	final int totalPhotos;
}
