#!/bin/bash


#TODO: Update the value of n to number of nodes allocated
np=5

# TODO: build your own builds and put the path of MPI libraries to be compared
OLD_MPI_HOME=/tmp/installed/
MPI_HOME=/tmp/installed/

# TODO: allocate node(s) using following command and run this script
# lalloc <# of nodes> -G guests -q pbatch


### generate desired hostfile, block distribution
### use 4 for full subscription
for ppn in 4
do
HFILE=/global/home/users/jain/project/tensorflow/horovod/examples/tensorflow2/allreduce/allreduce_hosts

let np=$np
echo "Test $np processes on..."
cat $HFILE

max_msg=4194304

newlogfile=./new-coll
oldlogfile=./old-coll

rm -f $newlogfile-* $oldlogfile-*

mpi_flags_default="MV2_USE_CUDA=1 MV2_USE_GPUDIRECT_RDMA=1 MV2_USE_GPUDIRECT_GDRCOPY=0 MV2_USE_RDMA_CM=0"

#cd $OLD_MPI_HOME/libexec/osu-micro-benchmarks/mpi/collective
#coll_tests=`find ./ -type f -executable`
#cd -
#coll_tests=( "bcast" "allgather" "allreduce")
coll_tests=( "allreduce")
set -x
set +x

for i in `seq 1 3`
do
    ### pt2pt
    for tname in "${coll_tests[@]}"
    do
        echo "Runing ${tname}...Iteration $i"
        $MPI_HOME/bin/mpirun_rsh -np $np --hostfile $HFILE $mpi_flags_default LD_PRELOAD=$MPI_HOME/lib/libmpi.so $MPI_HOME/libexec/osu-micro-benchmarks/get_local_rank $MPI_HOME/libexec/osu-micro-benchmarks/mpi/collective/osu_${tname} -m :$max_msg -d cuda >> $newlogfile-${tname}
        
        $OLD_MPI_HOME/bin/mpirun_rsh -np $np --hostfile $HFILE $mpi_flags_default LD_PRELOAD=$OLD_MPI_HOME/lib/libmpi.so $OLD_MPI_HOME/libexec/osu-micro-benchmarks/get_local_rank $OLD_MPI_HOME/libexec/osu-micro-benchmarks/mpi/collective/osu_${tname} -m :$max_msg -d cuda >> $oldlogfile-${tname}
    done
done

### SpectrumMPI
#mpirun -gpu -np 2 -npernode 1 --hostfile $HFILE hostname
#mpirun -gpu -np 2 --map-by node --hostfile $HFILE -x PAMI_IBV_ADAPTER_AFFINITY=0 /g/g91/chu30/mv2-src/osu-micro-benchmarks/omb-install-spectrum/libexec/osu-micro-benchmarks/mpi/pt2pt/osu_bw D D

echo "BEGIN{}
{
	msg = \$1
	lat = \$2
	
    if (msg > 0 && lat > 0) {
        avg_lat[msg] += lat
        cnt_lat[msg] ++
    }
}
END{
	for(m=4 ; m<=$max_msg ; m*=2)
		printf(\"%d\\t%f\\n\", m, avg_lat[m]/cnt_lat[m])
}
" > avg-latency.awk

echo "BEGIN{}
{
	msg = \$1
	bw = \$2

    if (msg != \"#\" && bw > 0) {
        avg_bw[msg] += (1/bw)
        cnt_bw[msg] ++
    }
}
END{
	for(m=1 ; m<=$max_msg ; m*=2) {
		printf(\"%d\\t%f\\n\", m, cnt_bw[m]/avg_bw[m])
    }
}
" > avg-bw.awk
cp avg-bw.awk avg-bibw.awk

echo "BEGIN{
print \"===\", tn, \": Check these messages manually (10%+ degradation)\"
    printf (\"Size\\t\\tOld\\t\\tNEW\\t\\tDiff\\n\")
}
{
	msg = \$1
	old = \$2
	new = \$4
    if (tn == \"bw\" || tn == \"bibw\")
        diff = (new-old)/new
    else
        diff = (old-new)/old

    if (diff < -0.1)
        printf (\"%d\\t\\t%.3f\\t\\t%.3f\\t\\t%.3f\\n\", msg, old, new, diff)
    else
        printf (\"%d\\t\\t%.3f\\t\\t%.3f\\n\", msg, old, new)
}
END{
}
" > avg-diff.awk

for tname in "${coll_tests[@]}"
do
    ### get average
    awk -f avg-latency.awk $newlogfile-${tname} > $newlogfile-${tname}.avg
    awk -f avg-latency.awk $oldlogfile-${tname} > $oldlogfile-${tname}.avg

    ### paste both numbers together
    paste $oldlogfile-${tname}.avg $newlogfile-${tname}.avg  > mix.${tname}.avg
    ### calculate diff and report where we have performance degradation > 10%
    awk -v tn="${tname}" -f avg-diff.awk mix.${tname}.avg
done
rm $HFILE avg-*.awk *.avg
#rm -f $newlogfile-* $oldlogfile-*
done
