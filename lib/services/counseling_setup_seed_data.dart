import 'counseling_setup_service.dart';

class CounselingSetupSeedData {
  static CounselingSetupItem _item(
    String label, {
    int sortOrder = 0,
    bool active = true,
  }) {
    return CounselingSetupItem(
      id: '',
      label: label,
      sortOrder: sortOrder,
      active: active,
    );
  }

  static final CounselingSetupConfig config = CounselingSetupConfig(
    academicPerformanceInformation: <String>[
      'Performing significantly below ability',
      'Decrease in participation',
      'Failure to complete in-class assignments',
      'Repeated failure to complete homework',
      'Poor test scores',
      'Significant drop in grades',
      'Tardiness',
      'Unprepared for class',
      'Easily frustrated',
      'Short attention span',
    ],
    physicalAttributes: <String>[
      'Sleeping in class',
      'Complaining of nausea/stomachache',
      'Poor motor skills',
      'Frequent cold-like symptoms',
      'Smelling of alcohol/marijuana',
      'Slurred speech',
      'Poor hygiene',
      'Frequently expressing concern about personal health',
      'Noticeable change in weight',
    ],
    crisisIndicators: <String>[
      'Suicidal ideations',
      'Recent death of a family member or close friend',
      'Recent major illness of a family member or close friend',
      'Family issues and concerns',
    ],
    atypicalBehavior: <String>[
      'Expresses desires to punish or seek revenge through harmful or deadly means',
      'Inappropriate sexual verbalization',
      'Trouble getting along with peers',
      'Socially withdrawn',
      'Expresses hopelessness, worthlessness, or helplessness',
      'Expresses extreme fear or anxiety',
      'Expresses anger toward authority figures',
      'Lies frequently',
      'Criticizes others or self excessively',
      'Dresses inappropriately',
    ],
    groups: <CounselingSetupGroup>[
      CounselingSetupGroup(
        id: CounselingSetupConfig.academicPerformanceKey,
        key: CounselingSetupConfig.academicPerformanceKey,
        title: 'Academic Performance Information',
        items: <CounselingSetupItem>[
          _item('Performing significantly below ability', sortOrder: 1),
          _item('Decrease in participation', sortOrder: 2),
          _item('Failure to complete in-class assignments', sortOrder: 3),
          _item('Repeated failure to complete homework', sortOrder: 4),
          _item('Poor test scores', sortOrder: 5),
          _item('Significant drop in grades', sortOrder: 6),
          _item('Tardiness', sortOrder: 7),
          _item('Unprepared for class', sortOrder: 8),
          _item('Easily frustrated', sortOrder: 9),
          _item('Short attention span', sortOrder: 10),
        ],
      ),
      CounselingSetupGroup(
        id: CounselingSetupConfig.physicalAttributesKey,
        key: CounselingSetupConfig.physicalAttributesKey,
        title: 'Physical Attributes',
        items: <CounselingSetupItem>[
          _item('Sleeping in class', sortOrder: 1),
          _item('Complaining of nausea/stomachache', sortOrder: 2),
          _item('Poor motor skills', sortOrder: 3),
          _item('Frequent cold-like symptoms', sortOrder: 4),
          _item('Smelling of alcohol/marijuana', sortOrder: 5),
          _item('Slurred speech', sortOrder: 6),
          _item('Poor hygiene', sortOrder: 7),
          _item(
            'Frequently expressing concern about personal health',
            sortOrder: 8,
          ),
          _item('Noticeable change in weight', sortOrder: 9),
        ],
      ),
      CounselingSetupGroup(
        id: CounselingSetupConfig.crisisIndicatorsKey,
        key: CounselingSetupConfig.crisisIndicatorsKey,
        title: 'Crisis Indicators',
        items: <CounselingSetupItem>[
          _item('Suicidal ideations', sortOrder: 1),
          _item(
            'Recent death of a family member or close friend',
            sortOrder: 2,
          ),
          _item(
            'Recent major illness of a family member or close friend',
            sortOrder: 3,
          ),
          _item('Family issues and concerns', sortOrder: 4),
        ],
      ),
      CounselingSetupGroup(
        id: CounselingSetupConfig.atypicalBehaviorKey,
        key: CounselingSetupConfig.atypicalBehaviorKey,
        title: 'Atypical Behavior',
        items: <CounselingSetupItem>[
          _item(
            'Expresses desires to punish or seek revenge through harmful or deadly means',
            sortOrder: 1,
          ),
          _item('Inappropriate sexual verbalization', sortOrder: 2),
          _item('Trouble getting along with peers', sortOrder: 3),
          _item('Socially withdrawn', sortOrder: 4),
          _item(
            'Expresses hopelessness, worthlessness, or helplessness',
            sortOrder: 5,
          ),
          _item('Expresses extreme fear or anxiety', sortOrder: 6),
          _item('Expresses anger toward authority figures', sortOrder: 7),
          _item('Lies frequently', sortOrder: 8),
          _item('Criticizes others or self excessively', sortOrder: 9),
          _item('Dresses inappropriately', sortOrder: 10),
        ],
      ),
    ],
  );
}
