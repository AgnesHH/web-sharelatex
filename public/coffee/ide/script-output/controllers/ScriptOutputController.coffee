define [
	"base"
], (App) ->
	App.controller "ScriptOutputController", ($scope, $http, ide, $anchorScroll, $location) ->
		reset = () ->
			$scope.needToUpgrade = ($scope.project.features.compileTimeout == 0)
			$scope.files = []
			$scope.output = []
			$scope.running = false
			$scope.error = false
			$scope.timedout = false
			$scope.session_id = Math.random().toString().slice(2)
		reset()
			
		$scope.uncompiled = true
		
		$scope.$on "editor:recompile", () ->
			$scope.run()
			
		ide.socket.on "clsiOutput", (message) ->
			# We get messages from other user's compiles in this project. Ignore them
			return if message.header?.session != $scope.session_id

			output = parseOutputMessage(message)
			if output?
				$scope.output.push output
				$scope.$apply()

		$scope.run = () ->
			return if $scope.running
			return if $scope.needToUpgrade
			
			reset()
			$scope.running = true
			$scope.uncompiled = false
			
			compiler = "python"
			extension = $scope.editor.open_doc.name.split(".").pop()?.toLowerCase()
			if extension == "r"
				compiler = "r"
			rootDoc_id = $scope.editor.open_doc_id
				
			doCompile(rootDoc_id, compiler)
				.success (data) ->
					$scope.running = false
					if data?.status == "timedout"
						$scope.timedout = true

				.error () ->
					$scope.running = false
					$scope.error = true
					
		doCompile = (rootDoc_id, compiler) ->
			url = "/project/#{$scope.project_id}/compile"
			$http
				.post(url, {
					_csrf: window.csrfToken
					# Always compile the open doc in this case
					rootDoc_id: rootDoc_id
					compiler: compiler
					session_id: $scope.session_id
				})
					
		parseAndLoadOutputFiles = (files = []) ->
			return files
				.map(parseOutputFile)
				.map(loadOutputFile)
				.filter(shouldShowOutputFile)
				.sort(sortOutputFiles)
		
		parseOutputMessage = (message) ->
			if message.msg_type == "stream"
				output = {
					output_type: message.content.name # 'stdout' or 'stderr'
					text: message.content.text
				}
			else if message.msg_type == "display_data"
				path = message.content.data['text/path']
				output = {
					output_type: "file"
					url: "/project/#{$scope.project_id}/output/#{path}?cache_bust=#{Date.now()}"
					file_type: "unknown"
					path: path
				}
				parts = path.split(".")
				if parts.length == 1
					extension = null
				else
					extension = parts[parts.length - 1].toLowerCase()
				output.extension = extension
				if extension in ["png", "jpg", "jpeg", "svg", "gif"]
					output.file_type = "image"
				else if extension in ["pdf"]
					output.file_type = "pdf"
				else if extension in ["rout"]
					output.file_type = "text"
			else
				output = null
			return output
			
