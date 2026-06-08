import 'package:flutter_test/flutter_test.dart';
import 'package:photo_album/models/entity/face_entity.dart';
import 'package:photo_album/models/entity/photo_entity.dart';
import 'package:photo_album/service/face_cluster_service.dart';

FaceEntity _face({
  required int id,
  required int photoId,
  required List<double> embedding,
  double qualityScore = 0.5,
  bool isPrimaryFace = true,
  String version = 'arcface_onnx_v1',
}) {
  return FaceEntity()
    ..id = id
    ..photoId = photoId
    ..assetId = 'asset_$photoId'
    ..faceIndex = 0
    ..left = 0
    ..top = 0
    ..right = 100
    ..bottom = 100
    ..embedding = embedding
    ..embeddingModelVersion = version
    ..qualityScore = qualityScore
    ..clusterId = null
    ..isPrimaryFace = isPrimaryFace
    ..createdAt = 0
    ..updatedAt = 0;
}

PhotoEntity _photo({
  required int id,
  List<String>? aiTags,
  int width = 300,
  int height = 300,
}) {
  return PhotoEntity()
    ..id = id
    ..assetId = 'asset_$id'
    ..path = '/tmp/$id.jpg'
    ..timestamp = 0
    ..width = width
    ..height = height
    ..aiTags = aiTags;
}

void main() {
  group('face_cluster_service', () {
    test(
      'clusters stable faces and leaves small unmatched cluster as leftover',
      () async {
        final faces = <FaceEntity>[
          _face(
            id: 1,
            photoId: 11,
            embedding: const [1.0, 0.0],
            qualityScore: 0.9,
          ),
          _face(
            id: 2,
            photoId: 12,
            embedding: const [0.99, 0.01],
            qualityScore: 0.8,
          ),
          _face(
            id: 3,
            photoId: 13,
            embedding: const [-1.0, 0.0],
            qualityScore: 0.9,
          ),
          _face(
            id: 4,
            photoId: 14,
            embedding: const [-0.99, -0.01],
            qualityScore: 0.8,
          ),
          _face(
            id: 5,
            photoId: 15,
            embedding: const [0.0, 1.0],
            qualityScore: 0.7,
          ),
        ];

        final summary =
            await FaceClusterService.forTest(
              facesLoader: () async => faces,
            ).reclusterAllFaces(
              minQualityScore: 0.2,
              minClusterSize: 2,
              seedToCentroidThreshold: 0.95,
              seedToCoverThreshold: 0.95,
              mergeSmallClusterThreshold: 0.85,
            );

        expect(summary.candidateFaceCount, 5);
        expect(summary.clusterCount, 2);
        expect(summary.clusteredFaceCount, 4);
        expect(summary.leftoverFaceCount, 1);
        expect(summary.clusters.every((cluster) => cluster.size == 2), isTrue);
      },
    );

    test(
      'low quality primary faces do not form seed clusters by themselves',
      () async {
        final faces = <FaceEntity>[
          _face(
            id: 1,
            photoId: 21,
            embedding: const [1.0, 0.0],
            qualityScore: 0.18,
            isPrimaryFace: true,
          ),
          _face(
            id: 2,
            photoId: 22,
            embedding: const [0.99, 0.01],
            qualityScore: 0.16,
            isPrimaryFace: true,
          ),
          _face(
            id: 3,
            photoId: 23,
            embedding: const [0.98, 0.02],
            qualityScore: 0.04,
            isPrimaryFace: true,
          ),
          _face(
            id: 4,
            photoId: 24,
            embedding: const [-1.0, 0.0],
            qualityScore: 0.04,
            isPrimaryFace: true,
          ),
        ];

        final summary =
            await FaceClusterService.forTest(
              facesLoader: () async => faces,
            ).reclusterAllFaces(
              minQualityScore: 0.03,
              seedQualityScore: 0.10,
              minClusterSize: 2,
              seedToCentroidThreshold: 0.90,
              seedToCoverThreshold: 0.90,
              mergeSmallClusterThreshold: 0.80,
              attachToClusterThreshold: 0.75,
            );

        expect(summary.clusterCount, 1);
        expect(summary.clusteredFaceCount, 3);
        expect(summary.leftoverFaceCount, 1);
        expect(summary.clusters.first.size, 3);
      },
    );

    test(
      'rejects obvious non-human meme or pet photos before clustering',
      () async {
        final faces = <FaceEntity>[
          _face(
            id: 1,
            photoId: 31,
            embedding: const [1.0, 0.0],
            qualityScore: 0.30,
          ),
          _face(
            id: 2,
            photoId: 32,
            embedding: const [0.99, 0.01],
            qualityScore: 0.28,
          ),
          _face(
            id: 3,
            photoId: 33,
            embedding: const [0.98, 0.02],
            qualityScore: 0.50,
          ),
        ];
        final photos = <PhotoEntity>[
          _photo(id: 31, aiTags: const <String>['人物自拍']),
          _photo(id: 32, aiTags: const <String>['人物自拍']),
          _photo(id: 33, aiTags: const <String>['宠物', '表情包/梗图']),
        ];

        final summary =
            await FaceClusterService.forTest(
              facesLoader: () async => faces,
              photosLoader: () async => photos,
            ).reclusterAllFaces(
              minQualityScore: 0.03,
              seedQualityScore: 0.10,
              minClusterSize: 2,
              seedToCentroidThreshold: 0.90,
              seedToCoverThreshold: 0.90,
            );

        expect(summary.candidateFaceCount, 2);
        expect(summary.clusterCount, 1);
        expect(summary.clusteredFaceCount, 2);
      },
    );

    test(
      'does not cluster deprecated MobileCLIP face baseline embeddings',
      () async {
        final faces = <FaceEntity>[
          _face(
            id: 1,
            photoId: 35,
            embedding: const [1.0, 0.0],
            qualityScore: 0.30,
            version: 'mobileclip2_face_baseline_v1',
          ),
          _face(
            id: 2,
            photoId: 36,
            embedding: const [0.99, 0.01],
            qualityScore: 0.28,
            version: 'mobileclip2_face_baseline_v1',
          ),
        ];

        final summary = await FaceClusterService.forTest(
          facesLoader: () async => faces,
        ).reclusterAllFaces();

        expect(summary.candidateFaceCount, 0);
        expect(summary.clusterCount, 0);
      },
    );

    test(
      'merges stable small clusters of the same identity in second pass',
      () async {
        final faces = <FaceEntity>[
          _face(
            id: 1,
            photoId: 41,
            embedding: const [1.0, 0.0],
            qualityScore: 0.30,
          ),
          _face(
            id: 2,
            photoId: 42,
            embedding: const [0.99, 0.01],
            qualityScore: 0.28,
          ),
          _face(
            id: 3,
            photoId: 43,
            embedding: const [0.90, 0.10],
            qualityScore: 0.27,
          ),
          _face(
            id: 4,
            photoId: 44,
            embedding: const [0.89, 0.11],
            qualityScore: 0.26,
          ),
        ];

        final summary =
            await FaceClusterService.forTest(
              facesLoader: () async => faces,
              photosLoader: () async => faces
                  .map(
                    (face) => _photo(
                      id: face.photoId,
                      aiTags: const <String>['人物自拍'],
                    ),
                  )
                  .toList(growable: false),
            ).reclusterAllFaces(
              minQualityScore: 0.03,
              seedQualityScore: 0.10,
              minClusterSize: 2,
              seedToCentroidThreshold: 0.995,
              seedToCoverThreshold: 0.995,
              clusterCentroidMergeThreshold: 0.99,
              clusterCoverMergeThreshold: 0.99,
            );

        expect(summary.clusterCount, 1);
        expect(summary.clusteredFaceCount, 4);
        expect(summary.clusters.first.size, 4);
      },
    );

    test(
      'only one representative face per photo participates in main clustering',
      () async {
        final faces = <FaceEntity>[
          _face(
            id: 1,
            photoId: 51,
            embedding: const [1.0, 0.0],
            qualityScore: 0.20,
            isPrimaryFace: true,
          ),
          _face(
            id: 2,
            photoId: 51,
            embedding: const [0.95, 0.05],
            qualityScore: 0.12,
            isPrimaryFace: false,
          ),
          _face(
            id: 3,
            photoId: 52,
            embedding: const [0.99, 0.01],
            qualityScore: 0.21,
            isPrimaryFace: true,
          ),
          _face(
            id: 4,
            photoId: 52,
            embedding: const [0.94, 0.06],
            qualityScore: 0.11,
            isPrimaryFace: false,
          ),
        ];

        final summary =
            await FaceClusterService.forTest(
              facesLoader: () async => faces,
              photosLoader: () async => faces
                  .map(
                    (face) => _photo(
                      id: face.photoId,
                      aiTags: const <String>['人物自拍'],
                    ),
                  )
                  .toList(growable: false),
            ).reclusterAllFaces(
              minQualityScore: 0.03,
              seedQualityScore: 0.10,
              minClusterSize: 2,
            );

        expect(summary.clusterCount, 1);
        expect(summary.clusters.first.size, 2);
        expect(
          summary.clusters.first.members
              .where((member) => member.isPrimaryFace)
              .length,
          2,
        );
      },
    );

    test(
      'small representative clusters can grow before minClusterSize filtering',
      () async {
        final faces = <FaceEntity>[
          _face(
            id: 1,
            photoId: 61,
            embedding: const [1.00, 0.00],
            qualityScore: 0.20,
          ),
          _face(
            id: 2,
            photoId: 62,
            embedding: const [0.99, 0.01],
            qualityScore: 0.19,
          ),
          _face(
            id: 3,
            photoId: 63,
            embedding: const [0.92, 0.08],
            qualityScore: 0.18,
          ),
          _face(
            id: 4,
            photoId: 64,
            embedding: const [0.91, 0.09],
            qualityScore: 0.17,
          ),
        ];

        final summary =
            await FaceClusterService.forTest(
              facesLoader: () async => faces,
              photosLoader: () async => faces
                  .map(
                    (face) => _photo(
                      id: face.photoId,
                      aiTags: const <String>['人物自拍'],
                    ),
                  )
                  .toList(growable: false),
            ).reclusterAllFaces(
              minQualityScore: 0.03,
              seedQualityScore: 0.10,
              minClusterSize: 3,
              seedToCentroidThreshold: 0.995,
              seedToCoverThreshold: 0.995,
              mergeSmallClusterThreshold: 0.985,
              attachToCoverThreshold: 0.98,
            );

        expect(summary.clusterCount, 1);
        expect(summary.clusteredFaceCount, 4);
        expect(summary.leftoverFaceCount, 0);
        expect(summary.clusters.first.size, 4);
      },
    );
  });
}
