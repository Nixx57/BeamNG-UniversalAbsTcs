(function () {
  'use strict'

  angular.module('beamng.apps')
    .directive('universalAbsTcs', [function () {
      return {
        templateUrl: '/ui/modules/apps/UniversalAbsTcs/app.html',
        replace: true,
        restrict: 'EA',
        link: function (scope) {
          function callUniversalAbsTcs (expression, callback) {
            bngApi.engineLua(
              '(function() extensions.load("universalAbsTcs"); return universalAbsTcs.' + expression + ' end)()',
              callback
            )
          }

          function syncCurrentValues () {
            callUniversalAbsTcs('getStatus()', function (status) {
              if (!status) return

              scope.$evalAsync(function () {
                if (typeof status.absEnabled === 'boolean') {
                  scope.absEnabled = status.absEnabled
                }
                if (typeof status.tcsEnabled === 'boolean') {
                  scope.tcsEnabled = status.tcsEnabled
                }
                if (status.mode === 'grip' || status.mode === 'performance') {
                  scope.mode = status.mode
                }
              })
            })
          }

          scope.absEnabled = false
          scope.tcsEnabled = false
          scope.mode = 'performance'

          scope.setAbsEnabled = function () {
            var enable = scope.absEnabled

            callUniversalAbsTcs('setAbsEnabled(' + (enable ? 'true' : 'false') + ')', function (success) {
              scope.$evalAsync(function () {
                if (success === false) scope.absEnabled = !enable
              })
            })
          }

          scope.setTcsEnabled = function () {
            var enable = scope.tcsEnabled

            callUniversalAbsTcs('setTcsEnabled(' + (enable ? 'true' : 'false') + ')', function (success) {
              scope.$evalAsync(function () {
                if (success === false) scope.tcsEnabled = !enable
              })
            })
          }

          scope.setMode = function () {
            var newMode = scope.mode
            var previousMode = newMode === 'grip' ? 'performance' : 'grip'

            callUniversalAbsTcs('setMode("' + newMode + '")', function (success) {
              scope.$evalAsync(function () {
                if (success === false) scope.mode = previousMode
              })
            })
          }

          syncCurrentValues()
        }
      }
    }])
})()
