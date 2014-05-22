module.directive('fold', [
	'pageService', function (page) {
		var foldableClass = 'foldable',
			folderClass = 'folder',
			foldClass = 'fold',
			foldedClass = 'folded',
			folderAttr = '[folder]',
			foldAttr = '[folded]',
			disabledClass = 'always_folded';

		var link = function ($scope, $element, $attrs) {
			$scope.id = $attrs.id;
			$scope.$storage = page.$sessionStorage;

			//

			$scope.foldable = true;

			$scope.enableFold = function () {
				$scope.foldable = true;

				$element.addClass(foldableClass);
				$element.find(folderAttr).addClass(folderClass);
				$element.find(foldAttr).addClass(foldClass);

				$scope.restoreFolding();
			};

			$scope.disableFold = function () {
				$scope.foldable = false;
				$element.removeClass(foldableClass);
				$element.removeClass(foldedClass); 
				$element.find(folderAttr).removeClass(folderClass);
				$element.find(folderAttr).removeClass(foldClass);
				$element.addClass(disabledClass);
			};

			//

			var folded = false;

			$scope.fold = function () {
				folded = true;
				if($scope.foldable){
					$element.addClass(foldedClass);
				}
				$scope.setFolding();
			};

			$scope.unfold = function () {
				folded = false;
				$element.removeClass(foldedClass);
				$scope.setFolding();
			};

			$scope.toggleFold = function (state) {
				if ($scope.foldable) {
					if ((angular.isDefined(state) && !state) || folded) {
						$scope.unfold();
					}
					else {
						$scope.fold();
					}
				}
			};

			//

			var isForgetful = function () {
				return angular.isDefined($attrs.forget) && (!$attrs.forget || $scope.$eval($attrs.forget));
			};

			$scope.setFolding = function () {
				if (!isForgetful()) {
					$scope.$storage['folding_' + $scope.id] = folded;
				}
			};

			$scope.getFolding = function () {
				if (isForgetful() || angular.isUndefined($scope.$storage['folding_' + $scope.id])) {
					return undefined;
				}

				return $scope.$storage['folding_' + $scope.id];
			};

			$scope.restoreFolding = function () {
				var gotFolded = $scope.getFolding();

				if (angular.isUndefined(gotFolded)) {
					gotFolded = angular.isDefined($attrs.closed) ? true : false;
				}

				if (gotFolded) {
					$scope.fold();
				}
				else {
					$scope.unfold();
				}
			};

			//

			if (angular.isDefined($attrs.fold) && (!$attrs.fold || $scope.$eval($attrs.fold))) {
				$scope.enableFold();
			}
			else {
				$scope.disableFold();
			}

			$scope.restoreFolding();
		};

		return {
			restrict: 'A',
			priority: 0,
			link: link
		}
	}
]);
