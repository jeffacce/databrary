'use strict';
app.directive('metadataForm', [
  'constantService', 'messageService', function(constants, messages) {
    return {
      restrict: 'E',
      templateUrl: 'volume/metadata.html',
      link: function($scope) {
        var form, volume;
        volume = $scope.volume;
        form = $scope.metadataForm;

        $(document).on('click', '.showinstruct, .uploadinstuction', function() {
          $('input[name="metadata"]').click();
        });

        $(document).on('change', 'input[name="metadata"]', function() {
          var file;
          file = $(this).val().replace(/C:\\fakepath\\/ig, '');
          $('.uploadinstuction').hide();
          $('.uploadsubmit').show(function(){
            $('.filename').addClass('padding');
          });
          $('.filename').text(file);
        });
        
        form.save = function() {
          var data;
          messages.clear(form);
          data = new FormData();
          data.append('file', form.data.metadata[0]);
          form.$setSubmitted();
          return volume.detectcsv(data).then(function() {
            $('metadata-match-form').show();
            form.validator.server({});
            messages.add({
              type: 'green',
              body: constants.message('volume.metadatadetect.success'),
              owner: form
            });
            form.$setPristine();
            var selected_mapping_array = [];
            for (var i = 0; i < volume.suggested_mapping.length; i++) {
              if(volume.suggested_mapping[i].compatible_csv_fields[0]){
                selected_mapping_array.push({"metric": volume.suggested_mapping[i].metric, "csv_field": volume.suggested_mapping[i].compatible_csv_fields[0]})
              }
            }
            volume.selected_mapping = selected_mapping_array;
            if(volume.selected_mapping.length === volume.suggested_mapping.length){
              $('metadata-form').hide();
            }
            for (var i = 0; i < volume.column_samples.length; i++) {
              for (var j = 0; j < volume.column_samples[i].samples.length; j++) {
                if(volume.column_samples[i].samples[j] === "") {
                  volume.column_samples[i].samples[j] = "null";
                  $('.nulltext').show();
                }
              }
            }
          }, function(res) {
            form.$setUnsubmitted();
            form.validator.server(res);
            messages.addError({
              body: constants.message('volume.metadatadetect.error'),
              report: res,
              owner: form
            });
          });
        };
      }
    };
  }
]);

app.directive('metadataMatchForm', [
  'constantService', 'messageService', function(constants, messages) {
    return {
      restrict: 'E',
      templateUrl: 'volume/metadatamatch.html',
      require: 'ngModel',
      link: function($scope, ctrl) {
        var form, volume;
        volume = $scope.volume;
        form = $scope.metadataMatchForm;
        form.save = function() {
          messages.clear(form);
          var data = { "csv_upload_id": volume.csv_upload_id, "selected_mapping": volume.selected_mapping};
          form.$setSubmitted();
          return volume.matchcsv(data).then(function() {
            form.validator.server({});
            messages.add({
              type: 'green',
              body: constants.message('volume.metadataupload.success'),
              owner: form
            });
            form.$setPristine();
            $scope.skiptrue = false;
          }, function(res) {
            form.$setUnsubmitted();
            form.validator.server(res);
            messages.addError({
              body: constants.message('volume.metadataupload.error'),
              report: res,
              owner: form
            });
          });
        };
        $scope.skip = function(){
          $scope.skiptrue = true;
        }
      }
    };
  }
]);
