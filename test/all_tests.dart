import 'data/tag_taxonomy_v2_test.dart' as tag_taxonomy_v2_test;
import 'effects/subtitle_effect_test.dart' as subtitle_effect_test;
import 'service/app_ai_settings_service_test.dart'
    as app_ai_settings_service_test;
import 'service/analysis_pipeline_queue_test.dart'
    as analysis_pipeline_queue_test;
import 'service/create_recommendation_service_test.dart'
    as create_recommendation_service_test;
import 'service/event_service_test.dart' as event_service_test;
import 'service/face_cluster_service_test.dart' as face_cluster_service_test;
import 'service/album_tag_browser_service_test.dart'
    as album_tag_browser_service_test;
import 'service/junk_photo_filter_service_test.dart'
    as junk_photo_filter_service_test;
import 'service/media_embedding_record_test.dart'
    as media_embedding_record_test;
import 'service/mobileclip_tag_service_test.dart'
    as mobileclip_tag_service_test;
import 'service/mobileclip2_semantic_index_service_test.dart'
    as mobileclip2_semantic_index_service_test;
import 'service/music_service_test.dart' as music_service_test;
import 'service/photo_attribute_background_service_test.dart'
    as photo_attribute_background_service_test;
import 'service/semantic_photo_search_service_test.dart'
    as semantic_photo_search_service_test;
import 'service/story_location_manifest_simulation_test.dart'
    as story_location_manifest_simulation_test;
import 'service/theme_cluster_service_test.dart' as theme_cluster_service_test;
import 'service/travel_memory_detector_test.dart'
    as travel_memory_detector_test;
import 'service/story_video_timeline_test.dart' as story_video_timeline_test;
import 'service/story_video_caption_persistence_test.dart'
    as story_video_caption_persistence_test;
import 'service/story_queue_order_test.dart' as story_queue_order_test;
import 'utils/dbscan_algorithm_test.dart' as dbscan_algorithm_test;
import 'utils/event_cluster_helper_test.dart' as event_cluster_helper_test;
import 'utils/story_prompt_helper_test.dart' as story_prompt_helper_test;
import 'utils/theme_subclustering_test.dart' as theme_subclustering_test;
import 'view/album_page_split_compile_test.dart'
    as album_page_split_compile_test;
import 'view/asset_backed_media_contract_test.dart'
    as asset_backed_media_contract_test;
import 'view/album_page_split_contract_test.dart'
    as album_page_split_contract_test;
import 'view/create_page_search_test.dart' as create_page_search_test;
import 'view/story_generation_progress_page_test.dart'
    as story_generation_progress_page_test;

void main() {
  tag_taxonomy_v2_test.main();
  subtitle_effect_test.main();
  app_ai_settings_service_test.main();
  analysis_pipeline_queue_test.main();
  album_tag_browser_service_test.main();
  create_recommendation_service_test.main();
  junk_photo_filter_service_test.main();
  mobileclip_tag_service_test.main();
  semantic_photo_search_service_test.main();
  album_page_split_contract_test.main();
  album_page_split_compile_test.main();
  asset_backed_media_contract_test.main();
  create_page_search_test.main();
  story_generation_progress_page_test.main();
  event_service_test.main();
  face_cluster_service_test.main();
  media_embedding_record_test.main();
  mobileclip2_semantic_index_service_test.main();
  music_service_test.main();
  photo_attribute_background_service_test.main();
  story_location_manifest_simulation_test.main();
  theme_cluster_service_test.main();
  travel_memory_detector_test.main();
  story_video_timeline_test.main();
  story_video_caption_persistence_test.main();
  story_queue_order_test.main();
  dbscan_algorithm_test.main();
  event_cluster_helper_test.main();
  story_prompt_helper_test.main();
  theme_subclustering_test.main();
}
