(function () {
  'use strict'

  angular.module('beamng.apps')
    .directive('universalAbsTcs', [function () {
      return {
        templateUrl: '/ui/modules/apps/UniversalAbsTcs/app.html',
        replace: true,
        restrict: 'EA',
        scope: true,
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
                if (status.mode === 'grip' || status.mode === 'performance' || status.mode === 'legacy') {
                  scope.mode = status.mode
                }
              })
            })
          }

          scope.absEnabled = false
          scope.tcsEnabled = false
          scope.mode = 'performance'

          scope.setAbsEnabled = function (targetState) {
            var enable = targetState !== undefined ? targetState : scope.absEnabled

            callUniversalAbsTcs('setAbsEnabled(' + (enable ? 'true' : 'false') + ')', function (success) {
              scope.$evalAsync(function () {
                if (success !== false) {
                  scope.absEnabled = enable
                } else {
                  scope.absEnabled = !enable
                }
              })
            })
          }

          scope.setTcsEnabled = function (targetState) {
            var enable = targetState !== undefined ? targetState : scope.tcsEnabled

            callUniversalAbsTcs('setTcsEnabled(' + (enable ? 'true' : 'false') + ')', function (success) {
              scope.$evalAsync(function () {
                if (success !== false) {
                  scope.tcsEnabled = enable
                } else {
                  scope.tcsEnabled = !enable
                }
              })
            })
          }

          scope.setMode = function (targetMode) {
            var newMode = targetMode || scope.mode
            var previousMode = scope.mode

            callUniversalAbsTcs('setMode("' + newMode + '")', function (success) {
              scope.$evalAsync(function () {
                if (success !== false) {
                  scope.mode = newMode
                } else {
                  scope.mode = previousMode
                }
              })
            })
          }

          scope.toggleAbs = function () {
            scope.setAbsEnabled(!scope.absEnabled)
          }

          scope.toggleTcs = function () {
            scope.setTcsEnabled(!scope.tcsEnabled)
          }

          scope.toggleMode = function (direction) {
            var modes = ['performance', 'grip', 'legacy']
            var currentIndex = modes.indexOf(scope.mode)
            var nextMode = modes[(currentIndex + direction + modes.length) % modes.length]
            scope.setMode(nextMode)
          }

          scope.$on('VehicleFocusChanged', syncCurrentValues)
          scope.$on('VehicleReset', syncCurrentValues)

          syncCurrentValues()
        }
      }
    }])
})()
