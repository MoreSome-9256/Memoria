import 'service/event_service_test.dart' as event_service_test;
import 'service/face_cluster_service_test.dart' as face_cluster_service_test;
import 'service/story_location_manifest_simulation_test.dart'
    as story_location_manifest_simulation_test;
import 'service/theme_cluster_service_test.dart' as theme_cluster_service_test;
import 'service/travel_memory_detector_test.dart'
    as travel_memory_detector_test;
import 'utils/dbscan_algorithm_test.dart' as dbscan_algorithm_test;
import 'utils/event_cluster_helper_test.dart' as event_cluster_helper_test;
import 'utils/story_prompt_helper_test.dart' as story_prompt_helper_test;
import 'utils/theme_subclustering_test.dart' as theme_subclustering_test;
import 'view/album_page_split_compile_test.dart'
    as album_page_split_compile_test;
import 'view/album_page_split_contract_test.dart'
    as album_page_split_contract_test;

void main() {
  album_page_split_contract_test.main();
  album_page_split_compile_test.main();
  event_service_test.main();
  face_cluster_service_test.main();
  story_location_manifest_simulation_test.main();
  theme_cluster_service_test.main();
  travel_memory_detector_test.main();
  dbscan_algorithm_test.main();
  event_cluster_helper_test.main();
  story_prompt_helper_test.main();
  theme_subclustering_test.main();
}
