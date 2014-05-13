module.controller('LoginView', [
	'$scope', 'pageService', function ($scope, page) {
		page.display.title = page.constants.message('page.title.login');

		//

		$scope.method = 'databrary';
		$scope.loginData = {};

		//

		$scope.switchMethod = function (method) {
			$scope.method = method;
		};

		$scope.showMethodLink = function (method) {
			return $scope.method != method;
		};

		//

		$scope.submitForm = function () {
			page.auth.login($scope.loginData);
		};
	}
]);
