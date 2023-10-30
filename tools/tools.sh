echo "=============WATERBUS TOOLS DART============"
echo "1. import_sorter"
echo "2. build_runner"

while :
do 
	read -p "Run with: " input
	case $input in
		1)
		flutter pub run import_sorter:main
		break
		;;
		2)
		flutter packages pub run build_runner build -d
		flutter pub run import_sorter:main
		dart fix --apply 
		break
        ;;
        *)
		;;
	esac
done